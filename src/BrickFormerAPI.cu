#include "BrickFormerAPI.h"

#include <memory>

#include "log.h"
#include "tinyformat.h"
#include "util/exceptions.h"
#include "util/json.hpp"

#define ARP_LOG_CONTEXT "BrickFormerAPI"

using namespace bf;

size_t BrickFormerAPI_curl_write_std_string(void* contents, size_t size, size_t n, void* user_data)
{
    size_t total_size = size * n;
    static_cast<std::string*>(user_data)->append(static_cast<char*>(contents), total_size);
    return total_size;
}

namespace
{
std::unique_ptr<BrickFormerAPI> g_brickformer_api = std::make_unique<BrickFormerAPI>();
} // namespace

BrickFormerAPI::BrickFormerAPI() {}

BrickFormerAPI::~BrickFormerAPI() {}

BrickFormerAPI& BrickFormerAPI::g()
{
    if (!g_brickformer_api) {
        g_brickformer_api = std::make_unique<BrickFormerAPI>();
    }
    return *g_brickformer_api;
}

std::string BrickFormerAPI::perform_request(const std::string& url) const
{
    /* Initialize CURL */

    std::string response;

    curl_global_init(CURL_GLOBAL_DEFAULT);
    CURL* curl = curl_easy_init();
    if (!curl) {
        throw CurlException("Failed to initialize CURL");
    }

    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, &BrickFormerAPI_curl_write_std_string);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "libcurl-agent/1.0");

    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);

    CURLcode response_code = curl_easy_perform(curl);

    curl_easy_cleanup(curl);
    curl_global_cleanup();

    /* */

    ARP_DEBUG("Requested \"%s\"; Response (code %d): \"%s\"", url, response_code, response);

    if (response_code != CURLE_OK) {
#ifndef NDEBUG
        throw CurlException("Could not reach BrickFormer endpoint. CURL error: %s", curl_easy_strerror(response_code));
#else
        throw CurlException("Could not reach BrickFormer endpoint");
#endif
    }

    return response;
}

std::string BrickFormerAPI::version()
{
    std::string json = g().perform_request(k_endpoint + "version");
    nlohmann::json json_ = nlohmann::json::parse(json);
    return json_.get<std::string>();
}

std::string BrickFormerAPI::getUserPlan(const std::string& userId)
{
    std::string url_fmt = k_endpoint + "license?user_id=%s";
    std::string url = tfm::format(url_fmt.c_str(), userId);
    std::string json = g().perform_request(url);
    nlohmann::json json_ = nlohmann::json::parse(json);
    CHECK_STATE(json_["user_id"].get<std::string>() == userId); // Paranoia
    return json_["plan"].get<std::string>();
}