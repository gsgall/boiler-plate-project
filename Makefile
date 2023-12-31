# Compiler settings
CXX = g++
CXXFLAGS = -std=c++20 -g -Wall -Werror

# Source file and executable name
SRC = main.C
EXE = main

# Directories
SRCDIR = src
INCDIR = include/boiler-plate-project
BUILDDIR = build

# Source and header files
SOURCES = $(wildcard $(SRCDIR)/*.C)
HEADERS = $(wildcard $(INCDIR)/*.h)
OBJECTS = $(patsubst $(SRCDIR)/%.C,$(BUILDDIR)/%.o,$(SOURCES))

# adding include to look in the conda environment
INCLUDE_PATH = -I$(CONDA_PREFIX)/include
# link instructions to look in the conda environment
LIBRARY_PATH = -L$(CONDA_PREFIX)/lib

# build just the reaction parser
$(EXE): $(OBJECTS)
	@$(CXX) $(CXXFLAGS) $(INCLUDE_PATH) $(LIBRARY_PATH) -I$(INCDIR) $(OBJECTS) $(SRC) -o $(EXE)

# build both reaction parser and yaml library
all: $(EXE)

# build all of the source files for the parser
$(BUILDDIR)/%.o: $(SRCDIR)/%.C
	@mkdir -p $(@D)
	@$(CXX) $(CXXFLAGS) -I$(INCDIR) $(INCLUDE_PATH) -c $< -o $@

# clean up the parser
clean:
	@rm -rf *.dSYM
	@rm -f $(EXE)
	@rm  -rf build/*
