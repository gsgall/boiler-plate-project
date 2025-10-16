#include <string>

class Bar
{
public:
  Bar(std::string test);
  ~Bar() = default;

private:
  const std::string _test;
};
