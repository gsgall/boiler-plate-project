#include "libfoo/Foo.h"
#include "libbar/Bar.h"
int
main()
{
  const auto bar = Bar("bar");
  const auto foo = Foo(bar, "foo");
  return EXIT_SUCCESS;
}
