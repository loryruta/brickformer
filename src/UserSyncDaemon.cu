#include "UserSyncDaemon.h"

#include <firebase/app.h>
#include <firebase/auth.h>
#include <firebase/firestore.h>
#include <iostream>

#include "log.h"
#include "ui/App.h"

#define ARP_LOG_CONTEXT "UserSyncDaemon"

using namespace bf;
using namespace firebase;

UserSyncDaemon::UserSyncDaemon(User& user) : m_user(user) {}

UserSyncDaemon::~UserSyncDaemon()
{
    m_should_stop = true;
    if (m_thread && m_thread->joinable()) {
        m_thread->join();
    }
}

void UserSyncDaemon::start()
{
    m_should_stop = false;
    m_thread = std::make_unique<std::thread>([this]() { thread_start(); });
}

void UserSyncDaemon::thread_start()
{
    CHECK_STATE(!m_user.is_anonymous(), "UserSyncDaemon cannot be started for anonymous users");

    const std::string uid = m_user.m_uid;

    // Authentication verifier
    firebase::auth::Auth* firebase_auth = g_app->firebase_auth();
    std::optional<firebase::Future<std::string>> auth_token_future;

    // Firestore document
    firestore::Firestore* firestore = firestore::Firestore::GetInstance(g_app->firebase_app());
    firestore::DocumentReference doc_ref = firestore->Collection("purchases").Document(uid);
    std::optional<Future<firestore::DocumentSnapshot>> doc_snapshot_future;

    StopWatch auth_token_renewal_stopwatch;
    StopWatch user_doc_retrieval_stopwatch;
    const double k_auth_token_renewal_interval = 10 * 60; // 10 minutes
    const double k_user_doc_retrieval_interval = 1 * 60;  // 1 minute

    bool first_iteration = true;

    while (!m_should_stop) {
        // ---------------------------------------------------------------- Authentication renewal

        if (!auth_token_future && auth_token_renewal_stopwatch.elapsed_seconds() > k_auth_token_renewal_interval ||
            first_iteration) {
            firebase::auth::User user = firebase_auth->current_user();
            if (!user.is_valid()) {
                // Not signed in
                if (user_auth_error) {
                    user_auth_error("User not signed in\nfirebase_auth->current_user() is invalid");
                }
            } else {
                // Renew the token ID if expired (duration 1h)
                auth_token_future = user.GetToken(true /* renew */);
                ARP_DEBUG("Requested authentication token renewal");
            }
            auth_token_renewal_stopwatch.reset();
        }
        if (auth_token_future) {
            if (auth_token_future->error() != firebase::auth::kAuthErrorNone ||
                auth_token_future->status() == kFutureStatusInvalid) {
                // Can't renew authentication token
                if (user_auth_error) {
                    std::string error_message = "Cannot renew authentication token";
                    if (auth_token_future->error()) {
                        error_message += std::string("\n") + auth_token_future->error_message();
                    }
                    user_auth_error(error_message);
                }
            } else if (auth_token_future->status() == firebase::kFutureStatusComplete) {
                // Auth token renewed
                ARP_INFO("Auth token renewed");
                auth_token_future.reset();
            } else if (auth_token_future->status() == firebase::kFutureStatusPending) {
                // Pending...
            } else {
                throw IllegalStateException("Unhandled state");
            }
        }

        // ---------------------------------------------------------------- User document retrieval

        if (!doc_snapshot_future && user_doc_retrieval_stopwatch.elapsed_seconds() > k_user_doc_retrieval_interval ||
            first_iteration) {
            doc_snapshot_future = doc_ref.Get();
            ARP_DEBUG("Requested user document");
            user_doc_retrieval_stopwatch.reset();
        }
        if (doc_snapshot_future) {
            if (doc_snapshot_future->status() == kFutureStatusInvalid ||
                doc_snapshot_future->error() != firestore::kErrorOk) {
                if (user_document_retrieve_error) {
                    std::string error_message = "Cannot retrieve user data";
                    if (doc_snapshot_future->error()) {
                        error_message += std::string("\n") + doc_snapshot_future->error_message();
                    }
                    user_document_retrieve_error(error_message);
                }
                doc_snapshot_future.reset();
            } else if (doc_snapshot_future->status() == kFutureStatusComplete) {
                const firestore::DocumentSnapshot* doc_snapshot = doc_snapshot_future->result();
                if (doc_snapshot->exists()) {
                    m_user.sync(*doc_snapshot);
                } else {
                    m_user.touch_sync();
                }
                doc_snapshot_future.reset();
            } else if (doc_snapshot_future->status() == kFutureStatusPending) {
                // Pending...
            } else {
                throw IllegalStateException("Unhandled state");
            }
        }

        first_iteration = false;

        std::this_thread::sleep_for(std::chrono::seconds(10));
    }
}
