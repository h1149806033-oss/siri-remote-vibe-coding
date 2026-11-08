using System.Text.Json;
using System.Text.Json.Serialization;

namespace BossRemote.Core;

public sealed class AppSettings
{
    public bool LaunchAtLogin { get; set; }
    public bool SiriSustainedKey { get; set; } = true;
    public ushort SiriVirtualKey { get; set; } = Vk.RControl;
    public bool PointerEnabled { get; set; } = true;
    public bool ScrollEnabled { get; set; } = true;
    public bool TapToClick { get; set; } = true;
    public bool PressFreeze { get; set; }
    public bool PressToDrag { get; set; } = true;
    public bool InvertPointerY { get; set; }
    public bool InvertScroll { get; set; }
    public double PointerSpeed { get; set; } = 1;
    public double ScrollSpeed { get; set; } = 1;
    public bool HistoryEnabled { get; set; } = true;
    public string Appearance { get; set; } = "dark";
    public bool GattSupplement { get; set; } = true;

    public void ResetInput()
    {
        PointerEnabled = true;
        ScrollEnabled = true;
        TapToClick = true;
        PressFreeze = false;
        PressToDrag = true;
        InvertPointerY = false;
        InvertScroll = false;
        PointerSpeed = 1;
        ScrollSpeed = 1;
    }
}

public sealed class AppProfile
{
    public string AppId { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public Dictionary<RemoteControl, ButtonAction> Actions { get; set; } = [];
    public Dictionary<RemoteControl, ButtonAction> HoldActions { get; set; } = [];

    public int OverrideCount => Actions.Count + HoldActions.Count;
}

public sealed class MappingStore
{
    public const int CurrentDefaultsVersion = 3;
    public Dictionary<RemoteControl, ButtonAction> Actions { get; set; } = RemoteCatalog.DefaultActions();
    public Dictionary<RemoteControl, ButtonAction> HoldActions { get; set; } = [];
    public Dictionary<string, AppProfile> Profiles { get; set; } = [];
    public int DefaultsVersion { get; set; } = CurrentDefaultsVersion;

    public ButtonAction Action(RemoteControl control, string? appId = null)
    {
        if (appId != null && Profiles.TryGetValue(appId, out var profile) &&
            profile.Actions.TryGetValue(control, out var over))
        {
            return over;
        }

        return Actions.TryGetValue(control, out var action) ? action : RemoteCatalog.DefaultAction(control);
    }

    public ButtonAction HoldAction(RemoteControl control, string? appId = null)
    {
        if (appId != null && Profiles.TryGetValue(appId, out var profile) &&
            profile.HoldActions.TryGetValue(control, out var over))
        {
            return over;
        }

        return HoldActions.TryGetValue(control, out var action) ? action : ButtonAction.None;
    }

    public void SetAction(RemoteControl control, ButtonAction action, string? appId = null)
    {
        if (appId == null)
        {
            Actions[control] = action;
            return;
        }

        var profile = Ensure(appId, appId);
        profile.Actions[control] = action;
    }

    public void SetHoldAction(RemoteControl control, ButtonAction action, string? appId = null)
    {
        if (appId == null)
        {
            HoldActions[control] = action;
            return;
        }

        var profile = Ensure(appId, appId);
        profile.HoldActions[control] = action;
    }

    public AppProfile Ensure(string appId, string displayName)
    {
        if (!Profiles.TryGetValue(appId, out var profile))
        {
            profile = new AppProfile { AppId = appId, DisplayName = displayName };
            Profiles[appId] = profile;
        }
        else if (!string.IsNullOrWhiteSpace(displayName))
        {
            profile.DisplayName = displayName;
        }

        return profile;
    }

    public void RemoveProfile(string appId) => Profiles.Remove(appId);

    public void ResetActions()
    {
        Actions = RemoteCatalog.DefaultActions();
        HoldActions = [];
        DefaultsVersion = CurrentDefaultsVersion;
    }

    public void MigrateDefaults()
    {
        if (DefaultsVersion >= CurrentDefaultsVersion)
        {
            return;
        }

        Replace(RemoteControl.Back, KeyBinding.Escape, KeyBinding.Delete);
        Replace(RemoteControl.PlayPause, KeyBinding.Space, KeyBinding.MediaPlayPause);
        Replace(RemoteControl.Select, KeyBinding.MediaPlayPause, KeyBinding.ReturnKey);
        DefaultsVersion = CurrentDefaultsVersion;
    }

    private void Replace(RemoteControl control, KeyBinding from, KeyBinding to)
    {
        if (Actions.TryGetValue(control, out var action) &&
            action.Kind == ActionKind.Key && action.Key == from)
        {
            Actions[control] = ButtonAction.FromKey(to);
        }
    }
}

public enum ActivityKind
{
    Button,
    Mapping,
    App,
}

public sealed record ActivityEvent(
    DateTime Date,
    ActivityKind Kind,
    RemoteControl? Control,
    string? ActionLabel,
    string? AppId,
    string? Detail,
    int Count = 1);

public sealed class HistoryStore
{
    private readonly List<ActivityEvent> events = [];
    public int Limit { get; init; } = 300;
    public IReadOnlyList<ActivityEvent> Events => events;

    public void Record(ActivityEvent activity)
    {
        if (events.Count > 0)
        {
            var last = events[0];
            if (last.Kind == ActivityKind.Button &&
                activity.Kind == ActivityKind.Button &&
                last.Control == activity.Control &&
                last.AppId == activity.AppId &&
                last.ActionLabel == activity.ActionLabel &&
                (activity.Date - last.Date).TotalSeconds < 0.7)
            {
                events[0] = last with { Date = activity.Date, Count = last.Count + 1 };
                return;
            }
        }

        events.Insert(0, activity);
        if (events.Count > Limit)
        {
            events.RemoveRange(Limit, events.Count - Limit);
        }
    }

    public void Clear() => events.Clear();

    public void Replace(IEnumerable<ActivityEvent> items)
    {
        events.Clear();
        events.AddRange(items.OrderByDescending(item => item.Date).Take(Limit));
    }
}

public enum BatteryChargeState
{
    Unknown,
    Charging,
    ExternalPower,
    OnBattery,
}

public sealed record BatterySample(DateTime Date, int Level, BatteryChargeState State);

public sealed class BatteryInsights
{
    private readonly List<BatterySample> samples = [];
    private DateTime? chargeStartedAt;
    private int? chargeStartLevel;
    private DateTime? lastRiseAt;
    private DateTime? lastSampleAt;

    public bool Connected { get; private set; }
    public int? Level { get; private set; }
    public BatteryChargeState ChargeState { get; private set; } = BatteryChargeState.Unknown;
    public bool IsCharging { get; private set; }
    public IReadOnlyList<BatterySample> Samples => samples;

    public void SetConnected(bool connected, int? level, DateTime now)
    {
        Connected = connected;
        if (connected && level is { } value)
        {
            Update(value, null, now);
        }

        if (!connected)
        {
            IsCharging = false;
            ChargeState = BatteryChargeState.Unknown;
            chargeStartedAt = null;
        }
    }

    public void Update(int level, BatteryChargeState? state, DateTime now)
    {
        var value = Math.Clamp(level, 0, 100);
        var previous = Level;
        var rose = previous is { } before && value > before;
        Level = value;
        if (state is { } next && next != BatteryChargeState.Unknown)
        {
            ChargeState = next;
        }

        if (rose)
        {
            chargeStartedAt ??= lastSampleAt ?? now;
            chargeStartLevel ??= previous;
            lastRiseAt = now;
        }
        else if (ChargeState == BatteryChargeState.Charging)
        {
            chargeStartedAt ??= now;
            chargeStartLevel ??= value;
        }

        lastSampleAt = now;

        if (ChargeState is BatteryChargeState.OnBattery or BatteryChargeState.ExternalPower)
        {
            chargeStartedAt = null;
            chargeStartLevel = null;
        }

        Expire(now);
        samples.Add(new BatterySample(now, value, ChargeState));
        if (samples.Count > 2000)
        {
            samples.RemoveRange(0, samples.Count - 2000);
        }
    }

    public void Expire(DateTime now)
    {
        if (ChargeState == BatteryChargeState.Charging)
        {
            IsCharging = Connected;
            return;
        }

        var window = Level >= 95 ? TimeSpan.FromMinutes(5) : Level >= 90 ? TimeSpan.FromMinutes(3) : TimeSpan.FromSeconds(90);
        var recent = lastRiseAt is { } rise && now - rise < window;
        IsCharging = Connected && recent;
        if (!recent)
        {
            chargeStartedAt = null;
        }
    }

    public double? ChargeRatePerHour(DateTime now)
    {
        if (chargeStartedAt is not { } started || chargeStartLevel is not { } start || Level is not { } level)
        {
            return null;
        }

        var hours = (now - started).TotalHours;
        var gained = level - start;
        if (hours < 2.0 / 60.0 || gained < 1)
        {
            return null;
        }

        return gained / hours;
    }

    public TimeSpan? ChargeTimeRemaining(DateTime now)
    {
        if (!IsCharging || Level is not { } level || level >= 100 || ChargeRatePerHour(now) is not { } rate || rate <= 0)
        {
            return null;
        }

        return TimeSpan.FromHours((100 - level) / rate);
    }
}

public static class ConfigFile
{
    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public static void Save(
        string path,
        AppSettings settings,
        MappingStore mappings,
        HistoryStore history,
        IReadOnlyList<BatterySample> battery)
    {
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var dto = ConfigDto.From(settings, mappings, history, battery);
        File.WriteAllText(path, JsonSerializer.Serialize(dto, Json));
    }

    public static (AppSettings Settings, MappingStore Mappings, HistoryStore History, List<BatterySample> Battery) Load(string path)
    {
        if (!File.Exists(path))
        {
            return (new AppSettings(), new MappingStore(), new HistoryStore(), []);
        }

        var dto = JsonSerializer.Deserialize<ConfigDto>(File.ReadAllText(path), Json) ?? new ConfigDto();
        var mappings = dto.ToMappings();
        mappings.MigrateDefaults();
        var history = new HistoryStore();
        history.Replace(dto.History.Select(item => item.ToEvent()));
        return (dto.ToSettings(), mappings, history, dto.Battery.Select(item => item.ToSample()).ToList());
    }

    private sealed class ConfigDto
    {
        public int Version { get; set; } = MappingStore.CurrentDefaultsVersion;
        public SettingsDto Settings { get; set; } = new();
        public Dictionary<string, ActionDto> Actions { get; set; } = [];
        public Dictionary<string, ActionDto> HoldActions { get; set; } = [];
        public List<ProfileDto> Profiles { get; set; } = [];
        public List<HistoryDto> History { get; set; } = [];
        public List<BatteryDto> Battery { get; set; } = [];

        public static ConfigDto From(
            AppSettings settings,
            MappingStore mappings,
            HistoryStore history,
            IReadOnlyList<BatterySample> battery) => new()
        {
            Version = mappings.DefaultsVersion,
            Settings = SettingsDto.From(settings),
            Actions = mappings.Actions.ToDictionary(pair => RemoteCatalog.Id(pair.Key), pair => ActionDto.From(pair.Value)),
            HoldActions = mappings.HoldActions.ToDictionary(pair => RemoteCatalog.Id(pair.Key), pair => ActionDto.From(pair.Value)),
            Profiles = mappings.Profiles.Values.Select(ProfileDto.From).ToList(),
            History = history.Events.Select(HistoryDto.From).ToList(),
            Battery = battery.Select(BatteryDto.From).ToList(),
        };

        public AppSettings ToSettings() => Settings.ToSettings();

        public MappingStore ToMappings()
        {
            var store = new MappingStore
            {
                DefaultsVersion = Version,
                Actions = RemoteCatalog.DefaultActions(),
                HoldActions = [],
            };
            foreach (var (id, action) in Actions)
            {
                if (RemoteCatalog.TryParseId(id, out var control))
                {
                    store.Actions[control] = action.ToAction();
                }
            }

            foreach (var (id, action) in HoldActions)
            {
                if (RemoteCatalog.TryParseId(id, out var control))
                {
                    store.HoldActions[control] = action.ToAction();
                }
            }

            foreach (var profile in Profiles)
            {
                store.Profiles[profile.AppId] = profile.ToProfile();
            }

            return store;
        }
    }

    private sealed class SettingsDto
    {
        public bool LaunchAtLogin { get; set; }
        public bool SiriSustainedKey { get; set; } = true;
        public ushort SiriVirtualKey { get; set; } = Vk.RControl;
        public bool PointerEnabled { get; set; } = true;
        public bool ScrollEnabled { get; set; } = true;
        public bool TapToClick { get; set; } = true;
        public bool PressFreeze { get; set; }
        public bool PressToDrag { get; set; } = true;
        public bool InvertPointerY { get; set; }
        public bool InvertScroll { get; set; }
        public double PointerSpeed { get; set; } = 1;
        public double ScrollSpeed { get; set; } = 1;
        public bool HistoryEnabled { get; set; } = true;
        public string Appearance { get; set; } = "dark";
        public bool GattSupplement { get; set; } = true;

        public static SettingsDto From(AppSettings settings) => new()
        {
            LaunchAtLogin = settings.LaunchAtLogin,
            SiriSustainedKey = settings.SiriSustainedKey,
            SiriVirtualKey = settings.SiriVirtualKey,
            PointerEnabled = settings.PointerEnabled,
            ScrollEnabled = settings.ScrollEnabled,
            TapToClick = settings.TapToClick,
            PressFreeze = settings.PressFreeze,
            PressToDrag = settings.PressToDrag,
            InvertPointerY = settings.InvertPointerY,
            InvertScroll = settings.InvertScroll,
            PointerSpeed = settings.PointerSpeed,
            ScrollSpeed = settings.ScrollSpeed,
            HistoryEnabled = settings.HistoryEnabled,
            Appearance = settings.Appearance,
            GattSupplement = settings.GattSupplement,
        };

        public AppSettings ToSettings() => new()
        {
            LaunchAtLogin = LaunchAtLogin,
            SiriSustainedKey = SiriSustainedKey,
            SiriVirtualKey = SiriVirtualKey,
            PointerEnabled = PointerEnabled,
            ScrollEnabled = ScrollEnabled,
            TapToClick = TapToClick,
            PressFreeze = PressFreeze,
            PressToDrag = PressToDrag,
            InvertPointerY = InvertPointerY,
            InvertScroll = InvertScroll,
            PointerSpeed = PointerSpeed,
            ScrollSpeed = ScrollSpeed,
            HistoryEnabled = HistoryEnabled,
            Appearance = Appearance,
            GattSupplement = GattSupplement,
        };
    }

    private sealed class ActionDto
    {
        public string Kind { get; set; } = "none";
        public string? Key { get; set; }

        public static ActionDto From(ButtonAction action) => new()
        {
            Kind = action.Kind switch
            {
                ActionKind.Key => "key",
                ActionKind.MouseClick => "mouse",
                ActionKind.HoldLeftButton => "drag",
                _ => "none",
            },
            Key = action.Key?.ToString(),
        };

        public ButtonAction ToAction() => Kind switch
        {
            "key" when Enum.TryParse<KeyBinding>(Key, out var key) => ButtonAction.FromKey(key),
            "mouse" => ButtonAction.MouseClick,
            "drag" => ButtonAction.HoldLeftButton,
            _ => ButtonAction.None,
        };
    }

    private sealed class ProfileDto
    {
        public string AppId { get; set; } = "";
        public string DisplayName { get; set; } = "";
        public Dictionary<string, ActionDto> Actions { get; set; } = [];
        public Dictionary<string, ActionDto> HoldActions { get; set; } = [];

        public static ProfileDto From(AppProfile profile) => new()
        {
            AppId = profile.AppId,
            DisplayName = profile.DisplayName,
            Actions = profile.Actions.ToDictionary(pair => RemoteCatalog.Id(pair.Key), pair => ActionDto.From(pair.Value)),
            HoldActions = profile.HoldActions.ToDictionary(pair => RemoteCatalog.Id(pair.Key), pair => ActionDto.From(pair.Value)),
        };

        public AppProfile ToProfile()
        {
            var profile = new AppProfile { AppId = AppId, DisplayName = DisplayName };
            foreach (var (id, action) in Actions)
            {
                if (RemoteCatalog.TryParseId(id, out var control))
                {
                    profile.Actions[control] = action.ToAction();
                }
            }

            foreach (var (id, action) in HoldActions)
            {
                if (RemoteCatalog.TryParseId(id, out var control))
                {
                    profile.HoldActions[control] = action.ToAction();
                }
            }

            return profile;
        }
    }

    private sealed class HistoryDto
    {
        public DateTime Date { get; set; }
        public ActivityKind Kind { get; set; }
        public string? Control { get; set; }
        public string? ActionLabel { get; set; }
        public string? AppId { get; set; }
        public string? Detail { get; set; }
        public int Count { get; set; } = 1;

        public static HistoryDto From(ActivityEvent activity) => new()
        {
            Date = activity.Date,
            Kind = activity.Kind,
            Control = activity.Control is { } control ? RemoteCatalog.Id(control) : null,
            ActionLabel = activity.ActionLabel,
            AppId = activity.AppId,
            Detail = activity.Detail,
            Count = activity.Count,
        };

        public ActivityEvent ToEvent() => new(
            Date,
            Kind,
            Control != null && RemoteCatalog.TryParseId(Control, out var control) ? control : null,
            ActionLabel,
            AppId,
            Detail,
            Count);
    }

    private sealed class BatteryDto
    {
        public DateTime Date { get; set; }
        public int Level { get; set; }
        public BatteryChargeState State { get; set; }

        public static BatteryDto From(BatterySample sample) => new()
        {
            Date = sample.Date,
            Level = sample.Level,
            State = sample.State,
        };

        public BatterySample ToSample() => new(Date, Level, State);
    }
}
