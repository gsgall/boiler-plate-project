#include <string>

class Foo
{
public:
  Foo(const std::string & test);
  ~Foo() = default;

private:
  const std::string _test;
};
