using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace OpenMeshWin.Core;

public class SingBoxApiClient
{
    private readonly HttpClient _httpClient;
    private readonly string _apiBaseUrl;

    public SingBoxApiClient(string apiBaseUrl = "http://127.0.0.1:9091")
    {
        _apiBaseUrl = apiBaseUrl;
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(5)
        };
    }

    public async Task<bool> SelectOutboundAsync(string groupName, string outboundTag)
    {
        var url = $"{_apiBaseUrl}/outbounds/{Uri.EscapeDataString(groupName)}";
        var payload = new { outbound = outboundTag };
        var jsonPayload = JsonSerializer.Serialize(payload);
        var content = new StringContent(jsonPayload, Encoding.UTF8, "application/json");

        try
        {
            var response = await _httpClient.PostAsync(url, content);
            // sing-box API returns 204 No Content on success
            if (response.IsSuccessStatusCode)
            {
                Console.WriteLine($"Successfully switched group '{groupName}' to outbound '{outboundTag}'.");
                return true;
            }

            var errorContent = await response.Content.ReadAsStringAsync();
            Console.WriteLine($"Error switching outbound: {response.StatusCode}. Details: {errorContent}");
            return false;
        }
        catch (HttpRequestException e)
        {
            Console.WriteLine($"HTTP request to sing-box API failed: {e.Message}");
            return false;
        }
        catch (Exception e)
        {
            Console.WriteLine($"An unexpected error occurred when calling sing-box API: {e.Message}");
            return false;
        }
    }
}
