#pragma once

namespace lego_builder
{
template<typename T, size_t MAX_LENGTH>
class StaticVector
{
private:
    T m_data[MAX_LENGTH];
    size_t m_next_i = 0;

public:
    __host__ __device__
    explicit StaticVector() = default;

    __host__ __device__
    ~StaticVector() = default;

    __host__ __device__
    void push_back(const T& element)
    {
        m_data[m_next_i] = element;
        ++m_next_i;
    }

    __host__ __device__
    void clear() { m_next_i = 0; }

    __host__ __device__
    T* data() const { return m_data; }

    __host__ __device__
    size_t size() const { return m_next_i; }

    __host__ __device__
    T& operator[](size_t i) { return m_data[i]; }

    __host__ __device__
    const T& operator[](size_t i) const { return m_data[i]; }
};
}
