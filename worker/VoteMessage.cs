using Newtonsoft.Json;

namespace Worker
{
    public sealed class VoteMessage
    {
        [JsonProperty("vote")]
        public string Vote { get; set; } = string.Empty;

        [JsonProperty("voter_id")]
        public string VoterId { get; set; } = string.Empty;
    }
}
