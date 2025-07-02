#include "SyncDaemon.h"

#include <iostream>

#include <firebase/app.h>
#include <firebase/auth.h>

#include "BrickFormerAPI.h"
#include "User.h"
#include "log.h"
#include "ui/App.h"
#include "ui/AuthScreen.h"

#define ARP_LOG_CONTEXT "SyncDaemon"

/* Configuration */
// clang-format off
#define VERIFY_AUTH_INTERVAL   double(2 * 60)
#define UPDATE_PLAN_INTERVAL   double(1 * 60)
#define CHECK_SOFTWARE_VERSION double(5 * 60)
// clang-format on

using namespace bf;
using namespace firebase;

namespace
{
/// Class to verify the authentication of the user and possibly renew the authentication token.
struct SyncDaemon_AuthVerifier {
    DEFINE_EXCEPTION(AuthException);

    StopWatch stopwatch;
    std::optional<firebase::Future<std::string>> auth_token_future;

    void update(bool force)
    {
        if (!auth_token_future && (force || stopwatch.elapsed_seconds() > VERIFY_AUTH_INTERVAL)) {
            send_request();
            stopwatch.reset();
        }
        read_request();
    }

private:
    void send_request()
    {
        firebase::auth::Auth* firebase_auth = g_app->firebase_auth();
        firebase::auth::User firebase_user = firebase_auth->current_user();
        bool is_valid = !firebase_user.is_valid();
        if (!is_valid) {
            if (User::get()) {
                throw AuthException("User not signed in");
            } else {
                return; // Didn't login yet
            }
        }
        // Renew the token ID if expired (duration 1h)
        ARP_DEBUG("Requesting renewal of the auth token...");
        auth_token_future = firebase_user.GetToken(true /* renew */);
    }

    void read_request()
    {
        if (!auth_token_future) return;
        if (auth_token_future->error() != firebase::auth::kAuthErrorNone ||
            auth_token_future->status() == kFutureStatusInvalid) {
            // Can't renew authentication token
            throw AuthException("Cannot renew auth token: %s", auth_token_future->error());
        } else if (auth_token_future->status() == firebase::kFutureStatusComplete) {
            // Auth token renewed
            ARP_DEBUG("Auth token renewed: %s", auth_token_future->result());
            auth_token_future.reset();
        } else if (auth_token_future->status() == firebase::kFutureStatusPending) {
            // Pending...
        } else {
            throw IllegalStateException("Unhandled firebase future state");
        }
    }
};

/// Class to update the local user plan (e.g. free, premium) based on the backend.
struct SyncDaemon_PlanUpdater {
    StopWatch stopwatch;

    void update(bool force)
    {
        std::unique_ptr<User>& user = User::get();
        if (!user) {
            return;
        }
        if (force || stopwatch.elapsed_seconds() > UPDATE_PLAN_INTERVAL) {
            check();
            stopwatch.reset();
        }
    }

private:
    void check()
    {
        auto& user = User::get();
        std::string plan = BrickFormerAPI::getUserPlan(user->uid()); // Could throw BrickFormerAPI::CurlException
        ARP_DEBUG("User plan is \"%s\" (ID: %s)", plan, user->uid());
        user->set_plan(plan);
    }
};

/// Class to check whether the local version matches with the latest published version.
/// Throw an error if it does not.
struct SyncDaemon_SoftwareVersionChecker {
    DEFINE_EXCEPTION(MismatchVersionException);

    StopWatch stopwatch;

    void update(bool force)
    {
        if (force || stopwatch.elapsed_seconds() > CHECK_SOFTWARE_VERSION) {
            check();
            stopwatch.reset();
        }
    }

private:
    void check()
    {
        std::string version = BrickFormerAPI::version();
        ARP_DEBUG("Current version \"%s\" (remote: \"%s\")", BF_GIT_VERSION, version);
        if (BF_GIT_VERSION == version) { // Not BF_GIT_VERSION_FULL as it includes also the commit hash
        } else {
            throw MismatchVersionException(
                "Mismatching version, please update the software. "
                "Your software version is \"%s\" while the latest published version is \"%s\".",
                BF_GIT_VERSION,
                version);
        }
    }
};
} // namespace

SyncDaemon::SyncDaemon() {}

SyncDaemon::~SyncDaemon()
{
    m_should_stop = true;
    if (m_thread && m_thread->joinable()) {
        m_thread->join();
    }
}

void SyncDaemon::start()
{
    m_should_stop = false;
    m_thread = std::make_unique<std::thread>([this]() { thread_start(); });
}

void SyncDaemon::thread_start()
{
    SyncDaemon_AuthVerifier auth_verifier;
    SyncDaemon_PlanUpdater plan_updater;
    SyncDaemon_SoftwareVersionChecker software_version_checker;

    bool first_iteration = true;

    while (!m_should_stop) {
        try {
            auth_verifier.update(first_iteration);
            if (force_plan_check) {
                plan_updater.update(true);
                force_plan_check = false;
            } else {
                plan_updater.update(first_iteration);
            }
            software_version_checker.update(first_iteration);

        } catch (BrickFormerAPI::CurlException& e) {
            g_app->set_screen(std::make_shared<AuthScreen>(e.what(), true /* severe_error */));
            break;
        } catch (SyncDaemon_AuthVerifier::AuthException& e) {
            // If AuthException is thrown, unset any logged-in user and redirect to the AuthScreen
            g_app->enqueue_job([]() { User::unset(); });
            g_app->set_screen(std::make_shared<AuthScreen>(e.what(), false));
        } catch (SyncDaemon_SoftwareVersionChecker::MismatchVersionException& e) {
            // If the local version mismatch the remote version, show error and close
            g_app->set_screen(std::make_shared<AuthScreen>(e.what(), true /* severe_error */));
            break;
        }

        std::this_thread::sleep_for(std::chrono::seconds(3));

        first_iteration = false;
    }
}
