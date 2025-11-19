using VideoDashboard.Interfaces;

namespace StubbedServices;

public class StubbedAnalyticsService : IAnalyticsService
{
    private readonly List<FakeVideoAnalyticsModel> _fakeVideoAnalytics = [
        new() { VideoId = "", Views = 0, Likes = 0, Dislikes = 0, Comments = [] },
        new() { VideoId = "", Views = 0, Likes = 0, Dislikes = 0, Comments = [] },
        new() { VideoId = "", Views = 0, Likes = 0, Dislikes = 0, Comments = [] },
    ];

    bool IAnalyticsService.IsServiceReady => true;

    IVideoAnalyticsModel IAnalyticsService.GetVideoAnalytics(string videoId)
        => _fakeVideoAnalytics.FirstOrDefault(videoAnalytics => videoAnalytics.VideoId == videoId)
            ?? throw new Exception($"Could not find VideoAnalytics(VideoId={videoId})");
}

public class FakeVideoAnalyticsModel : IVideoAnalyticsModel
{
    public required string VideoId { get; set; }
    public required int Views { get; set; }
    public required int Likes { get; set; }
    public required int Dislikes { get; set; }
    public required IEnumerable<string> Comments { get; set; }
}
