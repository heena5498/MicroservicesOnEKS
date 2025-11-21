using VideoDashboard.Interfaces;

namespace VideoDashboard.Web.Models;

public class IndexViewModel
{
    public required IEnumerable<IVideoModel> Videos { get; set; }
}
