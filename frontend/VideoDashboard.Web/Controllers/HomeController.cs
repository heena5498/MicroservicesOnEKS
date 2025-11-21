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
        return View();
    }

    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error()
    {
        return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
    }
}
