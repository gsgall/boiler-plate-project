#include <string>

class Bar;
class Foo
{
public:
  Foo(const Bar & bar, const std::string & test);
  ~Foo() = default;

private:
  const Bar & _bar;
  const std::string _test;
};
