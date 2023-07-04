TODO:

- tone()
- built in drawing fns: rect(), line(), text()
- save/load + autosave. use savestates including 65536 bytes memory and 1024 bytes save data

TODO:

- compile wasm to c at runtime with tcc & dynamic link in
- either that or use WAMR runtime for jit support
- either that or do neither

TODO:

- support building on targets other than macos-x86_64 (vendor/wasm2c/bin/wasm2c is a binary file)

TODO:

- remove wasm-rt-impl.c, wasm-rt-impl.h & replace with our own implementation
