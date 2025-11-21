using VideoDashboard.Interfaces;

namespace VideoDashboard.Web.Models;

public class VideoViewModel
{
    public required IVideoModel Video { get; set; }
    public required IVideoAnalyticsModel VideoAnalytics { get; set; }
}
