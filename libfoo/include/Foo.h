#include <string>

class Foo
{
public:
  Foo(std::string test);
  ~Foo() = default;

private:
  const std::string _test;
};
