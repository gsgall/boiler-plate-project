# Compiler and flags
CXX = g++
CXXFLAGS = -std=c++20 -Wall -Werror -g -fprofile-arcs -ftest-coverage

PROJECT_NAME = boiler-plate-project
PROJECT_SRC_DIR = ../src
PROJECT_INCLUDE_DIR = ../include/$(PROJECT_NAME)

HELPER_SRC_DIR = helpers/src
HELPER_INCLUDE_DIR = helpers/include

TEST_SRC_DIR = tests
TEST_BUILD_DIR = build
TEST_EXECUTABLE = run_tests

CONDA_LIB_DIR = $(CONDA_PREFIX)/lib
CONDA_INCLUDE_DIR = $(CONDA_PREFIX)/include

GTEST_LIBS = -lgtest -lgtest_main

TEST_LINKS = $(GTEST_LIBS)

PROJECT_SOURCES := $(wildcard $(PROJECT_SRC_DIR)/*.C)
PROJECT_OBJECTS := $(patsubst $(PROJECT_SRC_DIR)/%.C, $(TEST_BUILD_DIR)/%.o, $(PROJECT_SOURCES))

HELPER_SOURCES := $(wildcard $(HELPER_SRC_DIR)/*.C)
HELPER_OBJECTS := $(patsubst $(HELPER_SRC_DIR)/%.C, $(TEST_BUILD_DIR)/%.o, $(HELPER_SOURCES))

TEST_SOURCES := $(wildcard $(TEST_SRC_DIR)/*.C)
TEST_OBJECTS := $(patsubst $(TEST_SRC_DIR)/%.C, $(TEST_BUILD_DIR)/%.o, $(TEST_SOURCES))

HELPER_INCLUDE := helpers/include
PROJECT_INCLUDE := ../include


$(TEST_BUILD_DIR)/%.o: $(PROJECT_SRC_DIR)/%.C
	@mkdir -p build
	@echo $@
	@$(CXX) $(CXXFLAGS) -I$(CONDA_INCLUDE_DIR) -I$(PROJECT_INCLUDE_DIR) -c $< -o $@

$(TEST_BUILD_DIR)/%.o: $(HELPER_SRC_DIR)/%.C
	@mkdir -p build
	@echo $@
	@$(CXX) $(CXXFLAGS) -I$(HELPER_INCLUDE) -I$(CONDA_INCLUDE_DIR) -I$(PROJECT_INCLUDE_DIR) -c $< -o $@

$(TEST_BUILD_DIR)/%.o: $(TEST_SRC_DIR)/%.C
	@mkdir -p build
	@echo $@
	@$(CXX) $(CXXFLAGS) -I$(PROJECT_INCLUDE) -I$(HELPER_INCLUDE) -I$(CONDA_INCLUDE_DIR) -c $< -o $@

$(TEST_EXECUTABLE): $(TEST_OBJECTS) $(PROJECT_OBJECTS) $(HELPER_OBJECTS)
	@mkdir -p output
	@$(CXX) $(CXXFLAGS) -I$(PROJECT_INCLUDE) -I$(HELPER_INCLUDE) -I$(CONDA_INCLUDE_DIR) -L$(CONDA_LIB_DIR) -o $@ $^ $(TEST_LINKS)

.PHONY: all clean coverage clean-coverage

all: $(TEST_EXECUTABLE)

clean:
	@rm -rf $(TEST_BUILD_DIR)/*.o
	@rm -f $(TEST_EXECUTABLE)
	@rm -rf $(PROJECT_BUILD_DIR)/*.o
	@rm -rf coverage_report
	@rm -rf build/*.g*
	@rm -rf *.dSYM
	@rm -f *.out


coverage: all
	lcov --capture --directory . --output-file coverage.info
	lcov --remove coverage.info "*/include/*" -o coverage.info
	lcov --remove coverage.info "*/gtest/*" -o coverage.info
	lcov --remove coverage.info "*/v1/*" -o coverage.info
	lcov --remove coverage.info "*/test/*" -o coverage.info
	lcov --remove coverage.info "*/yaml-cpp/*" -o coverage.info
	lcov --remove coverage.info "*/fmt/*" -o coverage.info
	genhtml coverage.info --output-directory coverage_report
	open coverage_report/index.html

clean-coverage:
	@rm -rf coverage.info
