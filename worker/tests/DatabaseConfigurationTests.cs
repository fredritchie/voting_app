using Npgsql;
using Xunit;

namespace Worker.Tests
{
    public class DatabaseConfigurationTests
    {
        [Fact]
        public void BuildsRdsConnectionStringFromManagedSecret()
        {
            var connectionString = DatabaseConfiguration.FromJson(
                "{\"username\":\"voteapp\",\"password\":\"secret-value\"}",
                "{\"host\":\"database.example\",\"port\":5432}",
                "voting"
            );

            var parsed = new NpgsqlConnectionStringBuilder(connectionString);

            Assert.Equal("database.example", parsed.Host);
            Assert.Equal(5432, parsed.Port);
            Assert.Equal("voting", parsed.Database);
            Assert.Equal("voteapp", parsed.Username);
            Assert.Equal("secret-value", parsed.Password);
            Assert.Equal(SslMode.Require, parsed.SslMode);
        }
    }
}
