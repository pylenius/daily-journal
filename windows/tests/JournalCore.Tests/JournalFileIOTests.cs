using JournalCore;
using Xunit;

namespace JournalCore.Tests;

public sealed class JournalFileIOTests : IDisposable
{
    readonly string dir = Path.Combine(Path.GetTempPath(), "journal-tests-" + Guid.NewGuid().ToString("N"));
    readonly JournalFileIO io;

    public JournalFileIOTests()
    {
        Directory.CreateDirectory(dir);
        io = new JournalFileIO(dir);
    }

    public void Dispose() => Directory.Delete(dir, recursive: true);

    string Put(string name, string text)
    {
        var path = Path.Combine(dir, name);
        File.WriteAllText(path, text);
        return path;
    }

    [Fact]
    public void ListsOnlyEntryFilesNewestFirst()
    {
        Put("2026-09-03.md", "# a\n");
        Put("2026-09-04.md", "# b\n");
        Put("2026-09-04-DESKTOP.md", "conflict copy\n");
        Put("notes.md", "x\n");
        Assert.Equal(["2026-09-04", "2026-09-03"], io.ListEntryFiles().Select(f => f.Date));
    }

    [Fact]
    public void ToggleKeepsCrlfAndEveryOtherByte()
    {
        var path = Put("2026-09-05.md", "# T\r\n\r\n## Actions\r\n- [ ] one — source: x\r\n- [ ] two\r\n");
        var loaded = io.Toggle(path, 4, "- [ ] two");
        Assert.Equal("# T\r\n\r\n## Actions\r\n- [ ] one — source: x\r\n- [x] two\r\n", File.ReadAllText(path));
        Assert.Equal(io.Read(path).Hash, loaded.Hash);
        Assert.Empty(Directory.GetFiles(dir, ".*"));
    }

    [Fact]
    public void ToggleFailsWhenLineGone()
    {
        var path = Put("2026-09-05.md", "## Actions\n- [ ] one\n");
        Assert.Throws<LineEditException>(() => io.Toggle(path, 1, "- [ ] two"));
        Assert.Equal("## Actions\n- [ ] one\n", File.ReadAllText(path));
    }

    [Fact]
    public void StaleWriteIsRefused()
    {
        var path = Put("2026-09-06.md", "## Done\n- a\n");
        var hash = io.Read(path).Hash;
        File.WriteAllText(path, "## Done\n- a\n- written by the Mac\n");
        Assert.Throws<ChangedSinceLoadException>(() => io.Write(path, "## Done\n- mine\n", hash));
        Assert.Contains("written by the Mac", File.ReadAllText(path));
        io.Write(path, "## Done\n- mine\n", null);
        Assert.Equal("## Done\n- mine\n", File.ReadAllText(path));
    }

    [Fact]
    public void CaptureNeverOverwritesAndIsListed()
    {
        var now = new DateTimeOffset(2026, 9, 4, 9, 12, 33, TimeSpan.FromHours(3));
        var name = io.WriteCapture(CaptureKind.Action, "Call Noor", "Windows", now);
        var inbox = io.ListInbox();
        Assert.Single(inbox);
        Assert.Equal(name, inbox[0].FileName);
        Assert.Equal(CaptureKind.Action, inbox[0].Kind);
        Assert.Equal("Call Noor", inbox[0].Body);
        Assert.Throws<IOException>(() =>
        {
            using var _ = new FileStream(Path.Combine(io.InboxPath, name), FileMode.CreateNew);
        });
    }

    [Fact]
    public void ReadToleratesBom()
    {
        var path = Path.Combine(dir, "2026-09-07.md");
        File.WriteAllBytes(path, [0xEF, 0xBB, 0xBF, .. "# T\n"u8.ToArray()]);
        Assert.Equal("# T\n", io.Read(path).Text);
    }
}
