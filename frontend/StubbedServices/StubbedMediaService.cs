using VideoDashboard.Interfaces;

namespace StubbedServices;

public class StubbedMediaService : IMediaService
{
    private readonly List<FakeVideoModel> _fakeVideos = [
        new () { Id = "", Name = "", ThumbnailUri = "", VideoUri = "" },
        new () { Id = "", Name = "", ThumbnailUri = "", VideoUri = "" },
        new () { Id = "", Name = "", ThumbnailUri = "", VideoUri = "" },
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
