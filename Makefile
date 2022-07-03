# Download 'mini.nvim'
deps/mini.nvim:
	@mkdir -p deps
	git clone https://github.com/echasnovski/mini.nvim $@

# Run explicit checkout of `main` branch
mini_checkout: deps/mini.nvim
	cd deps/mini.nvim && git log -10 --oneline
