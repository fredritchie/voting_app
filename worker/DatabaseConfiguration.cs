using System;
using System.IO;
using Newtonsoft.Json;
using Npgsql;

namespace Worker
{
    public static class DatabaseConfiguration
    {
        public static string FromEnvironment()
        {
            var secretFile = Environment.GetEnvironmentVariable("DB_SECRET_FILE");
            if (string.IsNullOrWhiteSpace(secretFile))
            {
                throw new InvalidOperationException("DB_SECRET_FILE is required");
            }

            var metadataFile = Environment.GetEnvironmentVariable("DB_METADATA_FILE");
            if (string.IsNullOrWhiteSpace(metadataFile))
            {
                throw new InvalidOperationException("DB_METADATA_FILE is required");
            }

            var database = Environment.GetEnvironmentVariable("DB_NAME") ?? "voting";
            return FromJson(
                File.ReadAllText(secretFile),
                File.ReadAllText(metadataFile),
                database
            );
        }

        public static string FromJson(string secretJson, string metadataJson, string database)
        {
            var secret = JsonConvert.DeserializeObject<RdsSecret>(secretJson)
                ?? throw new InvalidOperationException("The RDS secret is empty or invalid");
            var metadata = JsonConvert.DeserializeObject<RdsMetadata>(metadataJson)
                ?? throw new InvalidOperationException("The RDS metadata is empty or invalid");

            if (string.IsNullOrWhiteSpace(metadata.Host) ||
                string.IsNullOrWhiteSpace(secret.Username) ||
                string.IsNullOrWhiteSpace(secret.Password))
            {
                throw new InvalidOperationException("The RDS configuration must contain host, username, and password");
            }

            var builder = new NpgsqlConnectionStringBuilder
            {
                Host = metadata.Host,
                Port = metadata.Port == 0 ? 5432 : metadata.Port,
                Database = database,
                Username = secret.Username,
                Password = secret.Password,
                SslMode = SslMode.Require,
                TrustServerCertificate = true,
            };

            return builder.ConnectionString;
        }

        private sealed class RdsSecret
        {
            [JsonProperty("username")]
            public string Username { get; set; }

            [JsonProperty("password")]
            public string Password { get; set; }
        }

        private sealed class RdsMetadata
        {
            [JsonProperty("host")]
            public string Host { get; set; }

            [JsonProperty("port")]
            public int Port { get; set; }
        }
    }
}
