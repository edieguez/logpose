NVIM ?= nvim
# A DST-observing zone, so the date tests exercise DST transitions.
TEST_TZ ?= America/New_York

.PHONY: test test-file lint format deps clean

deps: deps/mini.nvim

deps/mini.nvim:
	git clone --depth 1 --filter=blob:none https://github.com/echasnovski/mini.nvim $@

# Run the whole suite: `make test`
test: deps
	TZ=$(TEST_TZ) $(NVIM) --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run()"

# Run one file: `make test-file FILE=tests/test_date.lua`
test-file: deps
	TZ=$(TEST_TZ) $(NVIM) --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

lint:
	stylua --check lua plugin tests

format:
	stylua lua plugin tests

clean:
	rm -rf deps
