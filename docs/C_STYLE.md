These are style conventions for C code in this project

- Main.c file starts has int main function call in the beginning. For other modules, public functions from the respective header file should be at the top

- Each module should have a single clear responsibility that is obvious from its name

- Functions must follow this naming structure <module name>_<action>_<object>

This way it is easy to notice when a module performs action that is outside of its responsibility.

- Each function should be prefaced by a comment that explains what it does. Do not write the same comments in header files

- No module should be over 500LOC. Anything more is a good sign that a refactor is due.

- All functions should be under 20LOC and have no more than two levels of nesting

- No lines longer than 80 characters.

- No magic numbers. All magic numbers should have a const definition with a clear name.

- Handle errors in the beginning of the function.
