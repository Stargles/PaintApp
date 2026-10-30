using System.Reflection;
using System.Windows.Threading;
using Streamer.Core;
using Streamer.Core.Protocol;
using Streamer.Tests.TestSupport;
using Xunit;

namespace Streamer.Tests;

public class TrayShutdownTests
{
    private sealed class OwnedApplication : Streamer.Tray.App
    {
        protected override void OnStartup(System.Windows.StartupEventArgs e) { }
    }

    private static void SetField(object owner, string name, object value) =>
        typeof(Streamer.Tray.App).GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(owner, value);

    private static void CaptureOwnedUi(Streamer.Tray.MainWindow window)
    {
        var root = (System.Windows.FrameworkElement)window.Content;
        root.Measure(new System.Windows.Size(520, 760));
        root.Arrange(new System.Windows.Rect(0, 0, 520, 760));
        root.UpdateLayout();
        var status = (System.Windows.FrameworkElement)window.FindName("StatusText");
        var transfers = (System.Windows.FrameworkElement)window.FindName("TransferList");
        double width = Math.Max(status.ActualWidth, transfers.ActualWidth);
        double height = status.ActualHeight + transfers.ActualHeight + 16;
        var visual = new System.Windows.Media.DrawingVisual();
        using (var drawing = visual.RenderOpen())
        {
            drawing.DrawRectangle(System.Windows.Media.Brushes.White, null, new System.Windows.Rect(0, 0, width, height));
            drawing.DrawRectangle(new System.Windows.Media.VisualBrush(status), null,
                new System.Windows.Rect(0, 0, status.ActualWidth, status.ActualHeight));
            drawing.DrawRectangle(new System.Windows.Media.VisualBrush(transfers), null,
                new System.Windows.Rect(0, status.ActualHeight + 16, transfers.ActualWidth, transfers.ActualHeight));
        }
        var picture = new System.Windows.Media.Imaging.RenderTargetBitmap((int)Math.Ceiling(width), (int)Math.Ceiling(height),
            96, 96, System.Windows.Media.PixelFormats.Pbgra32);
        picture.Render(visual);
        var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder();
        encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(picture));
        using var file = File.Create(Path.Combine(AppContext.BaseDirectory, "tray-shutdown-owned-ui.png"));
        encoder.Save(file);
    }

    [Fact]
    public async Task ClickingQuitJoinsThePendingOutboxBeforeExitingAndStoppingItsPipeline()
    {
        string path = Path.Combine(Path.GetTempPath(), $"paintstreamer-quit-{Guid.NewGuid():N}.png");
        File.WriteAllBytes(path, new byte[] { 1 });
        var blocked = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var disposing = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var transport = new FakeFileTransport { HasClient = true };
        transport.BeforeSendAsync = async (_, ct) =>
        {
            blocked.TrySetResult();
            using var registration = ct.Register(() => disposing.TrySetResult());
            await release.Task;
        };
        var outbox = new FileOutbox(transport);
        var pump = (Task)typeof(FileOutbox).GetField("_pump", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(outbox)!;
        var pipeline = new FakePipeline();
        var session = new StreamerSession(@"C:\unused", createPipeline: (_, _) => Task.FromResult<ICapturePipeline>(pipeline));
        await session.SetSourceAsync(new CaptureSource { Kind = SourceKind.Monitor, Id = "0", Name = "test", Width = 64, Height = 64 });
        await session.OnClientConnectedAsync();
        var ready = new TaskCompletionSource<Action>(TaskCreationOptions.RunContinuationsAsynchronously);
        Exception? uiError = null;
        Streamer.Tray.MainWindow? window = null;
        Dispatcher? dispatcher = null;
        Action? requestShutdown = null;
        using var allowUi = new ManualResetEventSlim();
        Task? producer = null;
        var ui = new Thread(() =>
        {
            try
            {
                var app = new OwnedApplication { ShutdownMode = System.Windows.ShutdownMode.OnExplicitShutdown };
                SetField(app, "_fileOutbox", outbox);
                SetField(app, "_session", session);
                dispatcher = app.Dispatcher;
                requestShutdown = () => dispatcher.BeginInvoke(() => app.Shutdown());
                var settings = new Settings(path + ".settings.json");
                var server = new ProtocolServer(0, "test", "test", "test", "test", new FileInbox(settings));
                window = new Streamer.Tray.MainWindow(session, server, settings, outbox, new SessionLockMonitor(), _ => { });
                SetField(app, "_mainWindow", window);
                SetField(app, "_server", server);
                typeof(Streamer.Tray.App).GetMethod("SetUpTrayIcon", BindingFlags.Instance | BindingFlags.NonPublic)!
                    .Invoke(app, new object[] { (Action<string>)(_ => { }) });
                var icon = (System.Windows.Forms.NotifyIcon)typeof(Streamer.Tray.App)
                    .GetField("_trayIcon", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(app)!;
                var quit = icon.ContextMenuStrip!.Items.Cast<System.Windows.Forms.ToolStripItem>().Single(item => item.Text == "Quit");
                ready.TrySetResult(() => app.Dispatcher.BeginInvoke(() => quit.PerformClick()));
                app.Run();
            }
            catch (Exception error) { uiError = error; ready.TrySetException(error); }
        }) { IsBackground = true };
        ui.SetApartmentState(ApartmentState.STA);
        ui.Start();
        try
        {
            var clickQuit = await ready.Task.WaitAsync(TimeSpan.FromSeconds(10));
            var uiBlocked = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            dispatcher!.BeginInvoke(() =>
            {
                uiBlocked.TrySetResult();
                if (!allowUi.Wait(TimeSpan.FromSeconds(10))) throw new TimeoutException("Owned UI gate was not released");
            });
            await uiBlocked.Task.WaitAsync(TimeSpan.FromSeconds(10));
            object? firstOperation = null;
            var operationField = typeof(Streamer.Tray.MainWindow).GetField("_presentationOperation", BindingFlags.Instance | BindingFlags.NonPublic)!;
            var transferHandler = typeof(Streamer.Tray.MainWindow).GetMethod("FileOutbox_TransferUpdated", BindingFlags.Instance | BindingFlags.NonPublic)!;
            producer = Task.Run(() =>
            {
                for (int i = 0; i < 100; i++)
                {
                    window!.OnStatus(new StatusMessage { Streaming = false, Reason = $"tick{i}" });
                    if (i == 0) firstOperation = operationField.GetValue(window);
                }
                foreach (var state in new[] { OutboundFileState.Queued, OutboundFileState.Sending, OutboundFileState.Inserted })
                    transferHandler.Invoke(window, new object?[] { null, new OutboundFileEventArgs { Path = path, State = state } });
            });
            Assert.True(producer.Wait(TimeSpan.FromMilliseconds(500)), "Window status and transfer producers must not wait for the dispatcher");
            Assert.True(ReferenceEquals(firstOperation, operationField.GetValue(window)), "Exactly one pending window presentation must be reused");
            allowUi.Set();
            var picture = await dispatcher.InvokeAsync(() =>
            {
                var status = (System.Windows.Controls.TextBlock)window!.FindName("StatusText");
                var transfers = (System.Windows.Controls.ListBox)window.FindName("TransferList");
                return (status.Text, transfers.Items.Count, ((Streamer.Tray.TransferRowViewModel)transfers.Items[0]).StatusText);
            });
            await dispatcher.InvokeAsync(() => CaptureOwnedUi(window!));
            Assert.Equal(("Not streaming — tick99 — no client connected", 1, "Inserted on the iPad"), picture);
            // Paint attempt A as active, then hold the dispatcher while A finishes and
            // the same path is queued again. Each completed attempt keeps its own result.
            await dispatcher.InvokeAsync(() =>
            {
                foreach (var state in new[] { OutboundFileState.Queued, OutboundFileState.Sending })
                    transferHandler.Invoke(window, new object?[] { null, new OutboundFileEventArgs { Path = path, State = state } });
            });
            await dispatcher.InvokeAsync(() => { });
            var activeAttempt = await dispatcher.InvokeAsync(() =>
            {
                var transfers = (System.Windows.Controls.ListBox)window!.FindName("TransferList");
                return (transfers.Items.Count, ((Streamer.Tray.TransferRowViewModel)transfers.Items[0]).Terminal);
            });
            Assert.Equal((2, false), activeAttempt);
            allowUi.Reset();
            var retryUiBlocked = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            dispatcher.BeginInvoke(() =>
            {
                retryUiBlocked.TrySetResult();
                if (!allowUi.Wait(TimeSpan.FromSeconds(10))) throw new TimeoutException("Owned retry UI gate was not released");
            });
            await retryUiBlocked.Task.WaitAsync(TimeSpan.FromSeconds(10));
            producer = Task.Run(() =>
            {
                transferHandler.Invoke(window, new object?[] { null, new OutboundFileEventArgs { Path = path, State = OutboundFileState.Refused, Reason = "first attempt refused" } });
                // Repeated Queued notifications are waiting/progress, not new attempts.
                for (int i = 0; i < 100; i++)
                    transferHandler.Invoke(window, new object?[] { null, new OutboundFileEventArgs { Path = path, State = OutboundFileState.Queued } });
                for (int i = 0; i < 100; i++)
                    transferHandler.Invoke(window, new object?[] { null, new OutboundFileEventArgs { Path = path, State = OutboundFileState.Sending, BytesSent = i } });
                transferHandler.Invoke(window, new object?[] { null, new OutboundFileEventArgs { Path = path, State = OutboundFileState.Inserted } });
            });
            Assert.True(producer.Wait(TimeSpan.FromMilliseconds(500)), "Retry history producers must not wait for the dispatcher");
            var pendingTransfers = (System.Collections.IDictionary)typeof(Streamer.Tray.MainWindow)
                .GetField("_pendingTransfers", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(window)!;
            Assert.Equal(2, pendingTransfers.Values.Cast<System.Collections.IList>().Sum(attempts => attempts.Count));
            allowUi.Set();
            var history = await dispatcher.InvokeAsync(() =>
            {
                var transfers = (System.Windows.Controls.ListBox)window!.FindName("TransferList");
                return string.Join(" | ", transfers.Items.Cast<Streamer.Tray.TransferRowViewModel>().Select(row => row.StatusText));
            });
            Assert.Equal("Inserted on the iPad | Refused — first attempt refused | Inserted on the iPad", history);
            await dispatcher.InvokeAsync(() => CaptureOwnedUi(window!));
            await dispatcher.InvokeAsync(() =>
            {
                window!.OnStatus(new StatusMessage { Reason = "must not land" });
                transferHandler.Invoke(window, new object?[] { null, new OutboundFileEventArgs { Path = path, State = OutboundFileState.Queued } });
                typeof(Streamer.Tray.MainWindow).GetMethod("RetirePresentation", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(window, null);
            });
            window!.OnStatus(new StatusMessage { Reason = "after retirement" });
            transferHandler.Invoke(window, new object?[] { null, new OutboundFileEventArgs { Path = path, State = OutboundFileState.Failed } });
            await dispatcher.InvokeAsync(() => { });
            Assert.Null(operationField.GetValue(window));
            Assert.Empty(pendingTransfers);
            var sinks = (System.Collections.IEnumerable)typeof(StreamerSession).GetField("_sinks", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(session)!;
            Assert.DoesNotContain(sinks.Cast<object>(), sink => ReferenceEquals(sink, window));
            var handlers = (Delegate?)typeof(FileOutbox).GetField("TransferUpdated", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(outbox);
            Assert.DoesNotContain(handlers?.GetInvocationList() ?? Array.Empty<Delegate>(), handler => ReferenceEquals(handler.Target, window));
            var retiredPicture = await dispatcher.InvokeAsync(() => ((System.Windows.Controls.TextBlock)window.FindName("StatusText")).Text);
            Assert.Equal("Not streaming — tick99 — no client connected", retiredPicture);
            outbox.Enqueue(path);
            await blocked.Task.WaitAsync(TimeSpan.FromSeconds(10));
            clickQuit();
            await disposing.Task.WaitAsync(TimeSpan.FromSeconds(10));
            Assert.False(ui.Join(TimeSpan.FromMilliseconds(500)), "Quit must keep the dispatcher alive until its owned outbox pump finishes");
            Assert.False(pipeline.Stopped);
            var responsive = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            dispatcher!.BeginInvoke(() => responsive.TrySetResult());
            Assert.True(responsive.Task.Wait(TimeSpan.FromMilliseconds(500)), "Quit must release the dispatcher while joining its workers");
            release.TrySetResult();
            Assert.True(ui.Join(TimeSpan.FromSeconds(10)), "Quit must finish once the pump joins");
            Assert.Null(uiError);
            Assert.True(pipeline.Stopped);
        }
        finally
        {
            allowUi.Set();
            release.TrySetResult();
            if (producer != null) { try { await producer.WaitAsync(TimeSpan.FromSeconds(10)); } catch { } }
            if (ui.IsAlive) requestShutdown?.Invoke();
            await pump.WaitAsync(TimeSpan.FromSeconds(10));
            ui.Join(TimeSpan.FromSeconds(10));
            await session.DisposeAsync();
            File.Delete(path);
        }
    }
}
