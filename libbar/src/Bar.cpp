#include "Bar.h"

#include <iostream>

Bar::Bar(const std::string & test) : _test(test)
{
  std::cout << "We are in Bar" << std::endl;
  std::cout << test << std::endl;
}
