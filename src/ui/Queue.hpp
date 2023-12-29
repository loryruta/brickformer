#pragma once

#include <condition_variable>
#include <mutex>
#include <queue>

namespace lego_builder
{
template <typename T>
class Queue {
private:
    std::queue<T> m_queue;
    std::mutex m_mutex;

public:
    explicit Queue() = default;
    ~Queue() = default;

    /// Pushes an item into the queue.
    void push(const T& item)
    {
        std::unique_lock<std::mutex> lock(m_mutex);
        m_queue.push(item);
    }

    /// Pops an item from the queue. Throws an exception if empty.
    T pop()
    {
        std::unique_lock<std::mutex> lock(m_mutex);
        T item = m_queue.front();  // Exception if no element is present
        m_queue.pop();
        return item;
    }

    bool empty()
    {
        std::unique_lock<std::mutex> lock(m_mutex);
        return m_queue.empty();
    }
};
}
