using Newtonsoft.Json;
using Xunit;

namespace Worker.Tests
{
    public class VoteMessageTests
    {
        [Fact]
        public void DeserializesQueuePayload()
        {
            var message = JsonConvert.DeserializeObject<VoteMessage>(
                "{\"vote\":\"a\",\"voter_id\":\"voter-123\"}"
            );

            Assert.NotNull(message);
            Assert.Equal("a", message.Vote);
            Assert.Equal("voter-123", message.VoterId);
        }
    }
}
