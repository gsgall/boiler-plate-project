#include "Foo.h"

#include <fstream>
#include <sstream>
#include <iostream>
#include <stdexcept>

Foo::Foo(std::string test) : _test(test) { std::cout << _test << std::endl; }
