namespace VideoDashboard.Interfaces;

public interface IMediaService
{
    bool IsServiceReady { get; }
    IVideoModel GetVideo(string videoId);
    IEnumerable<IVideoModel> ListVideos();
}

public interface IVideoModel
{
    string Id { get; }
    string Name { get; }
    string ThumbnailUri { get; }
    string VideoUri { get; }
}
