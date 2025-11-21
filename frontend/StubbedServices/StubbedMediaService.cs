using VideoDashboard.Interfaces;

namespace StubbedServices;

public class StubbedMediaService : IMediaService
{
    private readonly List<FakeVideoModel> _fakeVideos = [
        new () { Id = "zuPt", Name = "Sample Video 1", ThumbnailUri = "/assets/thumbnails/1.jpg", VideoUri = "/assets/videos/1.mp4" },
        new () { Id = "l84w", Name = "Sample Video 2", ThumbnailUri = "/assets/thumbnails/2.jpg", VideoUri = "/assets/videos/2.mp4" },
        new () { Id = "CuQ1", Name = "Sample Video 3", ThumbnailUri = "/assets/thumbnails/3.jpg", VideoUri = "/assets/videos/3.mp4" },
    ];

    bool IMediaService.IsServiceReady => true;

    IVideoModel IMediaService.GetVideo(string videoId)
        => _fakeVideos.FirstOrDefault(video => video.Id == videoId)
            ?? throw new Exception($"Could not find Video(Id={videoId})");

    IEnumerable<IVideoModel> IMediaService.ListVideos() => _fakeVideos;
}

public class FakeVideoModel : IVideoModel
{
    public required string Id { get; set; }
    public required string Name { get; set; }
    public required string ThumbnailUri { get; set; }
    public required string VideoUri { get; set; }
}
