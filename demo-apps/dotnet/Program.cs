using Serilog;
using Serilog.Formatting.Compact;

// ============================================================================
// OBI Zero-Code Trace-Log Correlation: .NET Demonstration
// ============================================================================
// Why default .NET fails out-of-the-box:
// 1. Console.Out uses a StreamWriter with AutoFlush = false (4 KB buffering).
// 2. builder.Logging.AddConsole() delegates log emission to an asynchronous
//    System.Threading.Channels.Channel background worker thread (ConsoleLoggerProcessor).
//    Because the background thread does not match the HTTP worker thread,
//    eBPF kernel probes find NO trace context in traces_ctx_v1.
//
// The Solution:
// Configure a synchronous console sink (e.g., Serilog Console) or set
// AutoFlush = true so write() syscalls happen on the active request thread.
// ============================================================================

bool useSynchronousLogger = Environment.GetEnvironmentVariable("USE_SYNCHRONOUS_LOGGER") != "false";

var builder = WebApplication.CreateBuilder(args);

if (useSynchronousLogger)
{
    // ✅ RECOMMENDED FIX FOR OBI:
    // Serilog Console sink writes synchronously to stdout on the executing request thread.
    Log.Logger = new LoggerConfiguration()
        .Enrich.FromLogContext()
        .WriteTo.Console(new CompactJsonFormatter())
        .CreateLogger();

    builder.Host.UseSerilog();
    Console.WriteLine("{\"msg\":\"Starting .NET service with SYNCHRONOUS Serilog (OBI Compatible)\",\"level\":\"Information\"}");
}
else
{
    // ⚠️ BROKEN OUT-OF-THE-BOX SCENARIO:
    // Uses default ASP.NET Core AddConsole() background channel thread.
    // write() syscalls are executed by ConsoleLoggerProcessor thread -> NO TRACE ID!
    builder.Logging.ClearProviders();
    builder.Logging.AddConsole();
    Console.WriteLine("{\"msg\":\"Starting .NET service with ASYNCHRONOUS AddConsole() (OBI Correlation will FAIL)\",\"level\":\"Warning\"}");
}

var app = builder.Build();

app.MapGet("/healthz", () => Results.Ok("OK\n"));

app.MapGet("/checkout", (ILogger<Program> logger) =>
{
    // If useSynchronousLogger == true:
    // write() is called synchronously on this HTTP worker thread -> OBI INJECTS TRACE_ID!
    // If useSynchronousLogger == false:
    // message is queued to background thread -> NO TRACE_ID INJECTED!
    logger.LogInformation("Processing .NET customer order orderId={OrderId} amount={Amount}", 
        Guid.NewGuid().ToString()[..8], 89.95);

    return Results.Ok(new
    {
        status = "approved",
        platform = ".NET 8.0",
        logger_mode = useSynchronousLogger ? "synchronous-serilog" : "asynchronous-channel"
    });
});

var port = Environment.GetEnvironmentVariable("PORT") ?? "8086";
app.Run($"http://0.0.0.0:{port}");
