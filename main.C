#ifdef FOO
#include "libfoo/Foo.h"
#endif
#ifdef BAR
#include "libbar/Bar.h"
#endif
int
main()
{
#ifdef FOO
  const auto foo = Foo("foo");
#endif
#ifdef BAR
  const auto bar = Bar("bar");
#endif
  return EXIT_SUCCESS;
}
