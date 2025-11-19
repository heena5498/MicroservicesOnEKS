namespace VideoDashboard.Interfaces;

public interface IAnalyticsService
{
    bool IsServiceReady { get; }
    IVideoAnalyticsModel GetVideoAnalytics(string videoId);
}

public interface IVideoAnalyticsModel
{
    string VideoId { get; }
    int Views { get; }
    int Likes { get; }
    int Dislikes { get; }
    IEnumerable<string> Comments { get; }
}
