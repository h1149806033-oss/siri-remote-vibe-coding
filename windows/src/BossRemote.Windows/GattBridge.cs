using Windows.Foundation;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Enumeration;
using Windows.Storage.Streams;
using BossRemote.Core;

namespace BossRemote.Windows;

/// <summary>
/// 只读标准电池特征，并在打开补充通道时订阅通知。
/// 不写 Linux 桥接里的 F0 控制字节，也不把通知送进虚拟麦克风。
/// </summary>
internal sealed class GattBridge : IAsyncDisposable
{
    private static readonly Guid DeviceInfoService = Guid.Parse("0000180a-0000-1000-8000-00805f9b34fb");
    private static readonly Guid PnpId = Guid.Parse("00002a50-0000-1000-8000-00805f9b34fb");
    private static readonly Guid BatteryService = Guid.Parse("0000180f-0000-1000-8000-00805f9b34fb");
    private static readonly Guid BatteryLevel = Guid.Parse("00002a19-0000-1000-8000-00805f9b34fb");
    private static readonly Guid BatteryStatus = Guid.Parse("00002bed-0000-1000-8000-00805f9b34fb");

    private readonly List<IDisposable> subscriptions = [];
    private BluetoothLEDevice? device;

    public async Task ProbeAsync(
        bool subscribeReports,
        Action<string> log,
        Action<byte[]>? onReport,
        Action<int>? onBattery,
        Action<BatteryChargeState>? onCharge)
    {
        await StopAsync();
        try
        {
            var selector = BluetoothLEDevice.GetDeviceSelectorFromPairingState(true);
            var paired = await DeviceInformation.FindAllAsync(selector);
            log($"已配对 BLE 设备 {paired.Count} 个。正在查找 PnP 004C/0315。");
            foreach (var info in paired)
            {
                BluetoothLEDevice? candidate = null;
                try
                {
                    candidate = await BluetoothLEDevice.FromIdAsync(info.Id);
                    if (candidate == null)
                    {
                        continue;
                    }

                    if (!await IsA2854Async(candidate))
                    {
                        candidate.Dispose();
                        continue;
                    }

                    device = candidate;
                    candidate = null;
                    log($"GATT 命中 {info.Name}。");
                    await ReadBatteryAsync(log, onBattery, onCharge);
                    if (subscribeReports && onReport != null)
                    {
                        await SubscribeAsync(log, onReport, onBattery, onCharge);
                    }
                    else
                    {
                        log("GATT 补充通道已关闭，不订阅厂商通知。");
                    }

                    return;
                }
                catch (Exception ex)
                {
                    log($"读取 {info.Name} 失败：{ex.Message}");
                    candidate?.Dispose();
                }
            }

            log("没有从已配对 BLE 设备读到 A2854 的 PnP ID。HID 驱动可能独占了 GATT，这不等于遥控器没连上。");
        }
        catch (Exception ex)
        {
            log("BLE 探测失败：" + ex.Message);
        }
    }

    public async ValueTask DisposeAsync() => await StopAsync();

    private async Task<bool> IsA2854Async(BluetoothLEDevice candidate)
    {
        var services = await candidate.GetGattServicesForUuidAsync(DeviceInfoService, BluetoothCacheMode.Uncached);
        if (services.Status != GattCommunicationStatus.Success)
        {
            return false;
        }

        foreach (var service in services.Services)
        {
            var chars = await service.GetCharacteristicsForUuidAsync(PnpId, BluetoothCacheMode.Uncached);
            if (chars.Status != GattCommunicationStatus.Success)
            {
                continue;
            }

            foreach (var characteristic in chars.Characteristics)
            {
                var read = await characteristic.ReadValueAsync(BluetoothCacheMode.Uncached);
                if (read.Status != GattCommunicationStatus.Success)
                {
                    continue;
                }

                var bytes = ToBytes(read.Value);
                if (bytes.Length >= 5 &&
                    bytes[1] == 0x4C && bytes[2] == 0x00 &&
                    bytes[3] == 0x15 && bytes[4] == 0x03)
                {
                    return true;
                }
            }
        }

        return false;
    }

    private async Task ReadBatteryAsync(
        Action<string> log,
        Action<int>? onBattery,
        Action<BatteryChargeState>? onCharge)
    {
        if (device == null)
        {
            return;
        }

        var services = await device.GetGattServicesForUuidAsync(BatteryService, BluetoothCacheMode.Uncached);
        if (services.Status != GattCommunicationStatus.Success)
        {
            log("电池服务不可读：" + services.Status);
            return;
        }

        foreach (var service in services.Services)
        {
            await ReadOneAsync(service, BatteryLevel, log, bytes =>
            {
                if (bytes.Length > 0)
                {
                    onBattery?.Invoke(Math.Clamp((int)bytes[0], 0, 100));
                }
            });
            await ReadOneAsync(service, BatteryStatus, log, bytes =>
            {
                if (bytes.Length == 1 && MapCharge(bytes[0]) is { } state)
                {
                    onCharge?.Invoke(state);
                }
                else if (bytes.Length > 0)
                {
                    log("充电状态字节不是已记录的单字节值，保持未知。");
                }
            });
        }
    }

    private async Task SubscribeAsync(
        Action<string> log,
        Action<byte[]> onReport,
        Action<int>? onBattery,
        Action<BatteryChargeState>? onCharge)
    {
        if (device == null)
        {
            return;
        }

        var services = await device.GetGattServicesAsync(BluetoothCacheMode.Uncached);
        if (services.Status != GattCommunicationStatus.Success)
        {
            log("枚举 GATT 服务失败：" + services.Status);
            return;
        }

        var subscribed = 0;
        foreach (var service in services.Services)
        {
            var chars = await service.GetCharacteristicsAsync(BluetoothCacheMode.Uncached);
            if (chars.Status != GattCommunicationStatus.Success)
            {
                log($"服务 {service.Uuid} 特征不可读：{chars.Status}");
                continue;
            }

            foreach (var characteristic in chars.Characteristics)
            {
                var canNotify = characteristic.CharacteristicProperties.HasFlag(GattCharacteristicProperties.Notify);
                if (!canNotify)
                {
                    continue;
                }

                var status = await characteristic.WriteClientCharacteristicConfigurationDescriptorAsync(
                    GattClientCharacteristicConfigurationDescriptorValue.Notify);
                if (status != GattCommunicationStatus.Success)
                {
                    log($"订阅 {characteristic.Uuid} 失败：{status}");
                    continue;
                }

                TypedEventHandler<GattCharacteristic, GattValueChangedEventArgs> handler = (_, args) =>
                {
                    var bytes = ToBytes(args.CharacteristicValue);
                    if (characteristic.Uuid == BatteryLevel && bytes.Length > 0)
                    {
                        onBattery?.Invoke(Math.Clamp((int)bytes[0], 0, 100));
                    }
                    else if (characteristic.Uuid == BatteryStatus && bytes.Length == 1 && MapCharge(bytes[0]) is { } state)
                    {
                        onCharge?.Invoke(state);
                    }

                    onReport(bytes);
                };

                characteristic.ValueChanged += handler;
                subscriptions.Add(new Subscription(characteristic, handler));
                subscribed++;
            }
        }

        log(subscribed == 0
            ? "没有订到任何通知。语音和触控如果只走被 HID 占用的特征，这里不会有数据。"
            : $"已订阅 {subscribed} 个通知特征。收到的字节会交给同一套解析器；语音包只计数，不播放。");
    }

    private static async Task ReadOneAsync(
        GattDeviceService service,
        Guid uuid,
        Action<string> log,
        Action<byte[]> accept)
    {
        var chars = await service.GetCharacteristicsForUuidAsync(uuid, BluetoothCacheMode.Uncached);
        if (chars.Status != GattCommunicationStatus.Success)
        {
            log($"{uuid} 不可读：{chars.Status}");
            return;
        }

        foreach (var characteristic in chars.Characteristics)
        {
            var read = await characteristic.ReadValueAsync(BluetoothCacheMode.Uncached);
            if (read.Status == GattCommunicationStatus.Success)
            {
                accept(ToBytes(read.Value));
            }
            else
            {
                log($"读取 {uuid} 失败：{read.Status}");
            }
        }
    }

    private static BatteryChargeState? MapCharge(byte value) => value switch
    {
        0x3B => BatteryChargeState.Charging,
        0x2B => BatteryChargeState.ExternalPower,
        0x2F => BatteryChargeState.OnBattery,
        _ => null,
    };

    private static byte[] ToBytes(IBuffer buffer)
    {
        var reader = DataReader.FromBuffer(buffer);
        var bytes = new byte[buffer.Length];
        reader.ReadBytes(bytes);
        return bytes;
    }

    private async Task StopAsync()
    {
        foreach (var subscription in subscriptions)
        {
            subscription.Dispose();
        }

        subscriptions.Clear();
        if (device != null)
        {
            device.Dispose();
            device = null;
        }

        await Task.CompletedTask;
    }

    private sealed class Subscription : IDisposable
    {
        private readonly GattCharacteristic characteristic;
        private readonly TypedEventHandler<GattCharacteristic, GattValueChangedEventArgs> handler;

        public Subscription(
            GattCharacteristic characteristic,
            TypedEventHandler<GattCharacteristic, GattValueChangedEventArgs> handler)
        {
            this.characteristic = characteristic;
            this.handler = handler;
        }

        public void Dispose() => characteristic.ValueChanged -= handler;
    }
}
