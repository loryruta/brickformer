#pragma once

#include <string>

#include <curl/curl.h>

#include "util/exceptions.h"

namespace bf
{
class BrickFormerAPI
{
public:
    static inline const std::string k_endpoint = "https://brickformer.io/api/";

    DEFINE_EXCEPTION(CurlException);

public:
    explicit BrickFormerAPI();
    ~BrickFormerAPI();

    [[nodiscard]] static BrickFormerAPI& g();
    [[nodiscard]] static std::string version();
    [[nodiscard]] static std::string getUserPlan(const std::string& userId);

private:
    std::string perform_request(const std::string& url) const;
};
} // namespace bf
