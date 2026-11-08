using System.Runtime.InteropServices;
using BossRemote.Core;

namespace BossRemote.Windows;

internal sealed class SendInputSink : IPointerSink
{
    private const uint MouseMove = 0x0001;
    private const uint LeftDown = 0x0002;
    private const uint LeftUp = 0x0004;
    private const uint Wheel = 0x0800;
    private const uint KeyUp = 0x0002;
    private const uint Extended = 0x0001;
    private int wheelResidual;

    public void Move(int dx, int dy) =>
        Send(Mouse(dx, dy, MouseMove, 0));

    public void Scroll(int pixels)
    {
        wheelResidual += pixels;
        var ticks = wheelResidual / 40;
        if (ticks == 0)
        {
            return;
        }

        wheelResidual -= ticks * 40;
        Send(Mouse(0, 0, Wheel, unchecked((uint)(ticks * 120))));
    }

    public void Click()
    {
        Send(Mouse(0, 0, LeftDown, 0));
        Send(Mouse(0, 0, LeftUp, 0));
    }

    public void SetLeftButton(bool down) =>
        Send(Mouse(0, 0, down ? LeftDown : LeftUp, 0));

    public void Press(KeyChord chord)
    {
        var mods = Modifiers(chord.Modifiers, down: true).ToArray();
        if (mods.Length > 0)
        {
            Send(mods);
        }

        Send(Key(chord.VirtualKey, down: true, chord.Extended));
        Send(Key(chord.VirtualKey, down: false, chord.Extended));
        var release = Modifiers(chord.Modifiers, down: false).Reverse().ToArray();
        if (release.Length > 0)
        {
            Send(release);
        }
    }

    public void SetSustained(KeyChord chord, bool down) =>
        Send(Key(chord.VirtualKey, down, chord.Extended));

    public void Type(string text)
    {
        foreach (var ch in text)
        {
            var down = new INPUT
            {
                type = 1,
                U = new InputUnion
                {
                    ki = new KEYBDINPUT
                    {
                        wScan = ch,
                        dwFlags = 0x0004,
                    },
                },
            };
            var up = down;
            up.U.ki.dwFlags = 0x0004 | KeyUp;
            Send(down, up);
        }
    }

    private static IEnumerable<INPUT> Modifiers(KeyModifiers modifiers, bool down)
    {
        if (modifiers.HasFlag(KeyModifiers.Control)) yield return Key(0x11, down, false);
        if (modifiers.HasFlag(KeyModifiers.Shift)) yield return Key(0x10, down, false);
        if (modifiers.HasFlag(KeyModifiers.Alt)) yield return Key(0x12, down, false);
        if (modifiers.HasFlag(KeyModifiers.Windows)) yield return Key(0x5B, down, true);
    }

    private static INPUT Mouse(int dx, int dy, uint flags, uint data) => new()
    {
        type = 0,
        U = new InputUnion
        {
            mi = new MOUSEINPUT { dx = dx, dy = dy, mouseData = data, dwFlags = flags },
        },
    };

    private static INPUT Key(ushort vk, bool down, bool extended) => new()
    {
        type = 1,
        U = new InputUnion
        {
            ki = new KEYBDINPUT
            {
                wVk = vk,
                dwFlags = (down ? 0u : KeyUp) | (extended ? Extended : 0u),
            },
        },
    };

    private static void Send(params INPUT[] inputs)
    {
        if (inputs.Length == 0)
        {
            return;
        }

        _ = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint count, INPUT[] inputs, int size);

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public nint dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public nint dwExtraInfo;
    }
}
