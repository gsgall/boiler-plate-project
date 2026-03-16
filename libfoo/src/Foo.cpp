#include "Foo.h"

#include <iostream>
Foo::Foo(const Bar & bar, const std::string & test) : _bar(bar), _test(test)
{
  std::cout << "We are in Bar now" << std::endl;
  std::cout << test << std::endl;
}
