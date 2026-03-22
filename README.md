# vhdl-blockdiag

An Emacs package for VHDL block diagram generation and visualization.

## Approach 1: DSL → SVG Preview + VHDL Generation

This approach uses a lightweight DSL to define blocks and wires, which is then used to:
1. Render an interactive SVG diagram inline.
2. Generate VHDL entities and top-level wrappers.

### DSL Example (`.vbd` file)

```elisp
(block dac_ctrl
  :ports ((clk     :in  std_logic)
          (data    :in  slv(16))
          (spi_out :out std_logic)))

(block filter
  :ports ((clk    :in  std_logic)
          (x_in   :in  slv(16))
          (x_out  :out slv(16))))

(wire filter/x_out -> dac_ctrl/data)
(wire top/clk      -> filter/clk dac_ctrl/clk)
```

## Installation

### Vanilla Emacs

1. Clone this repository to your local machine:
   ```bash
   git clone https://github.com/pcanuto/vhdl-blockdiag.git ~/.emacs.d/lisp/vhdl-blockdiag
   ```

2. Add the following to your `init.el`:
   ```elisp
   (add-to-list 'load-path "~/.emacs.d/lisp/vhdl-blockdiag")
   (require 'vhdl-blockdiag)
   ```

### Doom Emacs

1. Add the package to `~/.doom.d/packages.el`:
   ```elisp
   (package! vhdl-blockdiag
     :recipe (:host github :repo "pcanuto/vhdl-blockdiag"))
   ```

2. Configure it in `~/.doom.d/config.el`:
   ```elisp
   (use-package! vhdl-blockdiag
     :mode ("\\.vbd\\'" . emacs-lisp-mode)
     :config
     (add-hook 'emacs-lisp-mode-hook
               (lambda ()
                 (when (string-match-p "\\.vbd\\'" (or (buffer-file-name) ""))
                   (vhdl-blockdiag-mode 1)))))
   ```

3. Run `doom sync` to install the package.

## Usage

1. Load `vhdl-blockdiag.el` in your Emacs.
2. Create a file with `.vbd` extension.
3. Use `vhdl-blockdiag-mode` (it should activate automatically).

### Keybindings

- `C-c C-c`: Render SVG preview.
- `C-c C-v`: Generate VHDL code.

### DSL Features

- **Block Definition**: `(block name :ports ((pname :dir type) ...))`
- **Wire Definition**: `(wire from -> to1 to2 ...)`
  - Use `top/port_name` for top-level ports.
  - Direction and types are inferred for `top` ports and internal signals.
