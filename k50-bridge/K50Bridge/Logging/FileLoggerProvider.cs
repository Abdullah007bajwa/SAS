using System.Collections.Concurrent;
using System.Text;

namespace K50Bridge.Logging;

public sealed class FileLoggerProvider : ILoggerProvider
{
    private readonly string _path;
    private readonly ConcurrentDictionary<string, FileLogger> _loggers = new();
    private readonly object _writeLock = new();

    public FileLoggerProvider(string path) => _path = path;

    public ILogger CreateLogger(string categoryName) =>
        _loggers.GetOrAdd(categoryName, name => new FileLogger(name, _path, _writeLock));

    public void Dispose() => _loggers.Clear();

    private sealed class FileLogger : ILogger
    {
        private readonly string _category;
        private readonly string _path;
        private readonly object _writeLock;

        public FileLogger(string category, string path, object writeLock)
        {
            _category = category;
            _path = path;
            _writeLock = writeLock;
        }

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => logLevel >= LogLevel.Information;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            if (!IsEnabled(logLevel)) return;

            var line = new StringBuilder()
                .Append(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"))
                .Append(" [")
                .Append(logLevel)
                .Append("] ")
                .Append(_category)
                .Append(": ")
                .Append(formatter(state, exception));

            if (exception != null)
                line.Append(" | ").Append(exception.Message);

            lock (_writeLock)
            {
                File.AppendAllText(_path, line.AppendLine().ToString(), Encoding.UTF8);
            }
        }
    }
}
