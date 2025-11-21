using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using VideoDashboard.Interfaces;
using VideoDashboard.Web.Models;

namespace VideoDashboard.Web.Controllers;

public class HomeController(IMediaService mediaService, IAnalyticsService analyticsService) : Controller
{
    private readonly IMediaService _mediaService = mediaService;
    private readonly IAnalyticsService _analyticsService = analyticsService;

    public IActionResult Index()
    {
        IndexViewModel model = new()
        {
            Videos = _mediaService.ListVideos(),
        };
        return View(model);
    }

    public IActionResult Video(string videoId)
    {
        VideoViewModel model = new()
        {
            Video = _mediaService.GetVideo(videoId),
            VideoAnalytics = _analyticsService.GetVideoAnalytics(videoId),
        };
        return View(model);
    }

    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error()
    {
        return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
    }
}
