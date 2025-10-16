#include <string>

class Bar
{
public:
  Bar(const std::string & test);
  ~Bar() = default;

private:
  const std::string _test;
};
