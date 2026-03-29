MINI_NVIM := deps/mini.nvim

$(MINI_NVIM):
	@mkdir -p deps
	git clone --depth 1 https://github.com/echasnovski/mini.nvim $(MINI_NVIM)

test: $(MINI_NVIM)
	nvim --headless -u tests/minimal_init.lua -c "lua MiniTest.run()"

test-file: $(MINI_NVIM)
	nvim --headless -u tests/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

.PHONY: test test-file
