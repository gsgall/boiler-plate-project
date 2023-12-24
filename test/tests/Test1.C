#include <gtest/gtest.h>
#include "boiler-plate-project/boiler-plate-project.h"

TEST(Test1, Equal)
{
  EXPECT_EQ(test_function(), "Success!");
}
