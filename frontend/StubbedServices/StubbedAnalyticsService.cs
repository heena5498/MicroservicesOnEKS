using VideoDashboard.Interfaces;

namespace StubbedServices;

public class StubbedAnalyticsService : IAnalyticsService
{
    private readonly List<FakeVideoAnalyticsModel> _fakeVideoAnalytics = [
        new()
        {
            VideoId = "zuPt",
            Views = 1,
            Likes = 100,
            Dislikes = 100,
            Comments = [
                "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse sed tortor id eros feugiat ullamcorper vel id ipsum. Nullam eu est leo. Maecenas ac elementum erat. Donec et semper mi. Nullam feugiat est nec suscipit efficitur. Morbi vestibulum tristique ipsum, ut aliquam metus pulvinar vel. Etiam gravida dolor sodales, semper sem facilisis, tempus sem. Aliquam molestie ante nibh, sed finibus orci iaculis non. Suspendisse eu tristique ex.",
                "Etiam rutrum erat rhoncus tempor ullamcorper. Integer felis nulla, euismod id ultricies vitae, varius a enim. Proin consectetur suscipit mi a commodo. Sed id vulputate ligula, nec imperdiet justo. Donec dolor elit, molestie eget nisi eu, dapibus pulvinar lorem. Aliquam pulvinar tincidunt eros, vel feugiat justo tincidunt ut. Morbi metus nunc, sodales ac leo consequat, volutpat suscipit enim.",
                "Cras ornare lectus ut rutrum sagittis. Suspendisse faucibus quis lacus eu placerat. Suspendisse ultrices purus non lectus feugiat, quis vulputate magna tristique. Suspendisse potenti. Duis rhoncus aliquam cursus. Class aptent taciti sociosqu ad litora torquent per conubia nostra, per inceptos himenaeos. Duis leo dolor, elementum at massa nec, porta vulputate nisi. Nam vitae consequat libero. Fusce quis arcu quis dui lacinia ultricies eu sit amet leo. Sed sit amet rutrum enim, sit amet semper ipsum. Vestibulum ultrices dolor eu est cursus, vitae semper nulla posuere. Donec auctor mauris quis erat condimentum iaculis. Phasellus fringilla ut sem id ullamcorper. Nunc arcu tellus, consequat id convallis nec, suscipit sit amet urna. Integer viverra diam quis lacus viverra convallis.",
                "Pellentesque et mattis nibh, a elementum sem. Nullam pharetra risus id libero volutpat, sit amet bibendum mi consequat. Morbi sed nunc scelerisque, viverra dui id, convallis ligula. Maecenas nec vulputate leo. Fusce eu leo eu purus aliquet finibus ac nec dui. Phasellus vestibulum ullamcorper tempus. Aliquam nec libero quam. Donec tincidunt nulla ut nulla scelerisque dictum. Phasellus ac risus erat. Integer sed ex pellentesque, mollis diam vel, interdum arcu. Pellentesque eget malesuada neque. Nulla bibendum metus arcu. Aenean nulla nibh, vulputate at tincidunt eget, tristique eu turpis. Nullam molestie sed nibh in ornare. Donec volutpat ultrices turpis. Maecenas molestie accumsan arcu.",
                "Curabitur tincidunt dignissim nibh non hendrerit. Mauris ultrices, magna eget dignissim feugiat, velit risus vulputate ligula, cursus mollis augue nunc et elit. Vivamus euismod sollicitudin ultrices. Proin interdum vulputate diam, a aliquam tellus molestie et. Nam in posuere nulla, malesuada dictum urna. Nullam volutpat turpis augue, quis vulputate urna vulputate quis. Etiam nec euismod dui, vel vulputate dolor. Etiam scelerisque nulla sit amet pharetra vulputate. Nullam varius hendrerit augue, ac viverra lacus fermentum vitae. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae;",
            ],
        },
        new() { VideoId = "l84w", Views = 2, Likes = 0, Dislikes = 0, Comments = [] },
        new() { VideoId = "CuQ1", Views = 3, Likes = 0, Dislikes = 0, Comments = [] },
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
