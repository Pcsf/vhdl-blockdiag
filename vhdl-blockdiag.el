;;; vhdl-blockdiag.el --- VHDL Block Diagram Generator  -*- lexical-binding: t; -*-

;; Author: pcanuto
;; Keywords: vhdl, hardware, tools
;; Version: 0.1

;;; Commentary:
;; This package implements a DSL for VHDL block diagrams,
;; providing SVG visualization and VHDL code generation.

;;; Code:

(require 'cl-lib)
(require 'svg)

(defgroup vhdl-blockdiag nil
  "VHDL Block Diagram customization."
  :group 'languages)

;;; Data Structures

(defvar-local vhdl-blockdiag--blocks nil
  "List of blocks in the current diagram.
Each block is an alist: ((name . \"block_name\") (ports . (...)))")

(defvar-local vhdl-blockdiag--wires nil
  "List of wires in the current diagram.
Each wire is an alist: ((from . \"block/port\") (to . (\"block/port\" ...)))")

;;; Parser

(defun vhdl-blockdiag--parse-port (port-spec)
  "Parse a port specification (NAME :DIR TYPE)."
  (let ((name (car port-spec))
        (dir  (cadr port-spec))
        (type (cl-caddr port-spec)))
    `((name . ,(symbol-name name))
      (dir  . ,(substring (symbol-name dir) 1)) ; remove :
      (type . ,(if (stringp type) type (symbol-name type))))))

(defun vhdl-blockdiag--parse-block (spec)
  "Parse a block specification (block NAME :ports (...))."
  (let ((name (cadr spec))
        (ports (cl-getf (cddr spec) :ports)))
    (push `((name . ,(symbol-name name))
            (ports . ,(mapcar #'vhdl-blockdiag--parse-port ports)))
          vhdl-blockdiag--blocks)))

(defun vhdl-blockdiag--parse-wire (spec)
  "Parse a wire specification (wire FROM -> TO1 TO2 ...)."
  (let* ((from (cadr spec))
         (to   (nthcdr 3 spec)))
    (push `((from . ,(symbol-name from))
            (to   . ,(mapcar #'symbol-name to)))
          vhdl-blockdiag--wires)))

(defun vhdl-blockdiag-parse-buffer ()
  "Parse the current buffer for block and wire definitions."
  (interactive)
  (setq vhdl-blockdiag--blocks nil
        vhdl-blockdiag--wires nil)
  (save-excursion
    (goto-char (point-min))
    (while (not (eobp))
      (let ((form (ignore-errors (read (current-buffer)))))
        (when (listp form)
          (cond
           ((eq (car form) 'block) (vhdl-blockdiag--parse-block form))
           ((eq (car form) 'wire)  (vhdl-blockdiag--parse-wire form))))))))

;;; Layout Engine (Simple Grid)

(defun vhdl-blockdiag--get-port-coords (block-name port-name layout)
  "Get the (x . y) coordinates of a port."
  (let* ((block (cl-find block-name layout :key (lambda (b) (cdr (assoc 'name b))) :test #'string=))
         (bx (cdr (assoc 'x block)))
         (by (cdr (assoc 'y block)))
         (ports (cdr (assoc 'ports block)))
         (port-idx 0)
         (found-port nil))
    (while (and ports (not found-port))
      (if (string= (cdr (assoc 'name (car ports))) port-name)
          (setq found-port (car ports))
        (setq port-idx (1+ port-idx)
              ports (cdr ports))))
    (when found-port
      (let ((pdir (cdr (assoc 'dir found-port))))
        (cons (if (string= pdir "in") bx (+ bx 150))
              (+ by 40 (* port-idx 15)))))))

(defun vhdl-blockdiag--layout-blocks ()
  "Assign simple grid coordinates to blocks."
  (let ((x 50) (y 50) (spacing 200))
    (mapcar (lambda (block)
              (prog1
                  (append block `((x . ,x) (y . ,y)))
                (setq x (+ x spacing))))
            (reverse vhdl-blockdiag--blocks))))
;;; SVG Renderer

(defun vhdl-blockdiag-render-svg ()
  "Render the current block diagram as an SVG."
  (interactive)
  (vhdl-blockdiag-parse-buffer)
  (let* ((layout (vhdl-blockdiag--layout-blocks))
         (width (+ 100 (* (length layout) 200)))
         (height 400)
         (svg (svg-create width height :stroke "black" :fill "white"))
         (buffer (get-buffer-create "*vhdl-blockdiag-preview*")))
    ;; Background
    (svg-rectangle svg 0 0 width height :fill "#fdfdfd")

    ;; Draw wires first so they are behind blocks
    (dolist (wire vhdl-blockdiag--wires)
...
      (let* ((from-spec (split-string (cdr (assoc 'from wire)) "/"))
             (from-block (car from-spec))
             (from-port (cadr from-spec))
             (from-coords (vhdl-blockdiag--get-port-coords from-block from-port layout)))
        (when from-coords
          (dolist (to-spec-str (cdr (assoc 'to wire)))
            (let* ((to-spec (split-string to-spec-str "/"))
                   (to-block (car to-spec))
                   (to-port (cadr to-spec))
                   (to-coords (vhdl-blockdiag--get-port-coords to-block to-port layout)))
              (when to-coords
                (svg-line svg (car from-coords) (cdr from-coords)
                          (car to-coords) (cdr to-coords)
                          :stroke "gray" :stroke-width 2)))))))

    ;; Draw blocks
    (dolist (block layout)
      (let ((bx (cdr (assoc 'x block)))
            (by (cdr (assoc 'y block)))
            (name (cdr (assoc 'name block))))
        (svg-rectangle svg bx by 150 100 :rx 5 :fill "white" :stroke "black")
        (svg-text svg name :x (+ bx 75) :y (+ by 20)
                  :text-anchor "middle" :font-family "sans-serif" :font-size "14" :fill "black" :font-weight "bold")
        ;; Draw ports
        (let ((py (+ by 40)))
          (dolist (port (cdr (assoc 'ports block)))
            (let ((pname (cdr (assoc 'name port)))
                  (pdir  (cdr (assoc 'dir port))))
              (svg-text svg pname :x (if (string= pdir "in") (+ bx 5) (- (+ bx 150) 5))
                        :y py :text-anchor (if (string= pdir "in") "start" "end")
                        :font-size "10" :fill "blue")
              (setq py (+ py 15)))))))

    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (svg-insert-svg svg)
        (display-buffer buffer)))))

;;; VHDL Emitter

(defun vhdl-blockdiag--get-wire-signal (wire-from wires)
  "Generate a signal name for a wire starting from WIRE-FROM using WIRES list."
  (if (string-prefix-p "top/" wire-from)
      (cadr (split-string wire-from "/"))
    (let* ((wire (cl-find wire-from wires :key (lambda (w) (cdr (assoc 'from w))) :test #'string=))
           (to-list (cdr (assoc 'to wire)))
           (top-to (cl-find "top/" to-list :test (lambda (prefix s) (string-prefix-p prefix s)))))
      (if top-to
          (cadr (split-string top-to "/"))
        (format "wire_%s" (replace-regexp-in-string "/" "_" wire-from))))))

(defun vhdl-blockdiag--get-port-type (block-name port-name blocks)
  "Get the type of a port."
  (let* ((block (cl-find block-name blocks :key (lambda (b) (cdr (assoc 'name b))) :test #'string=))
         (ports (cdr (assoc 'ports block)))
         (port (cl-find port-name ports :key (lambda (p) (cdr (assoc 'name p))) :test #'string=)))
    (cdr (assoc 'type port))))

(defun vhdl-blockdiag-generate-vhdl ()
  "Generate VHDL top-level code from the current diagram."
  (interactive)
  (vhdl-blockdiag-parse-buffer)
  (let ((buffer (get-buffer-create "*vhdl-blockdiag-vhdl*"))
        (blocks vhdl-blockdiag--blocks)
        (wires vhdl-blockdiag--wires)
        (top-ports nil))
    
    ;; Identify top-level ports and their types
    (dolist (wire wires)
      (let* ((from (cdr (assoc 'from wire)))
             (from-spec (split-string from "/")))
        (if (string-prefix-p "top/" from)
            (let* ((pname (cadr from-spec))
                   (first-to (car (cdr (assoc 'to wire))))
                   (to-spec (split-string first-to "/"))
                   (type (vhdl-blockdiag--get-port-type (car to-spec) (cadr to-spec) blocks)))
              (push `(,pname . ("in" . ,type)) top-ports))
          (dolist (to (cdr (assoc 'to wire)))
            (when (string-prefix-p "top/" to)
              (let* ((pname (cadr (split-string to "/")))
                     (type (vhdl-blockdiag--get-port-type (car from-spec) (cadr from-spec) blocks)))
                (push `(,pname . ("out" . ,type)) top-ports)))))))

    (with-current-buffer buffer
      (erase-buffer)
      (insert "-- Auto-generated VHDL by vhdl-blockdiag\n\n")
      (insert "library ieee;\nuse ieee.std_logic_1164.all;\n\n")
      (insert "entity top is\n  port (\n")
      (let ((unique-top (cl-remove-duplicates top-ports :test #'equal)))
        (cl-loop for (port-info . rest) on unique-top do
                 (let ((pname (car port-info))
                       (pdir (car (cdr port-info)))
                       (ptype (cdr (cdr port-info))))
                   (insert (format "    %s : %s %s%s\n" 
                                   pname pdir (or ptype "std_logic") (if rest ";" ""))))))
      (insert "  );\nend entity top;\n\n")
      (insert "architecture rtl of top is\n\n")
      
      ;; Components
      (dolist (block (reverse blocks))
        (insert (format "  component %s is\n    port (\n" (cdr (assoc 'name block))))
        (let ((ports (cdr (assoc 'ports block))))
          (cl-loop for (port . rest) on ports do
                   (insert (format "      %s : %s %s%s\n"
                                   (cdr (assoc 'name port))
                                   (cdr (assoc 'dir port))
                                   (cdr (assoc 'type port))
                                   (if rest ";" "")))))
        (insert "    );\n  end component;\n\n"))

      ;; Signals (only for internal wires)
      (dolist (wire wires)
        (let* ((from (cdr (assoc 'from wire)))
               (from-spec (split-string from "/"))
               (sig-name (vhdl-blockdiag--get-wire-signal from wires)))
          (unless (or (string-prefix-p "top/" from)
                      (cl-find sig-name top-ports :key #'car :test #'string=))
            (let ((type (vhdl-blockdiag--get-port-type (car from-spec) (cadr from-spec) blocks)))
              (insert (format "  signal %s : %s;\n"
                              sig-name (or type "std_logic")))))))
      
      (insert "\nbegin\n\n")
      
      ;; Port Maps
      (dolist (block (reverse blocks))
        (let ((bname (cdr (assoc 'name block))))
          (insert (format "  u_%s : %s\n    port map (\n" bname bname))
          (let ((mapped-ports nil))
            (dolist (port (cdr (assoc 'ports block)))
              (let* ((pname (cdr (assoc 'name port)))
                     (full-pname (format "%s/%s" bname pname))
                     (signal-name nil))
                ;; Find wire connected to this port
                (dolist (wire wires)
                  (let ((from (cdr (assoc 'from wire))))
                    (if (string= from full-pname)
                        (setq signal-name (vhdl-blockdiag--get-wire-signal from wires))
                      (dolist (to (cdr (assoc 'to wire)))
                        (when (string= to full-pname)
                          (setq signal-name (vhdl-blockdiag--get-wire-signal from wires)))))))
                (when signal-name
                  (push (format "      %s => %s" pname signal-name) mapped-ports))))
            (cl-loop for (map . rest) on (reverse mapped-ports) do
                     (insert map (if rest ",\n" "\n"))))
          (insert "    );\n\n")))
      
      (insert "end architecture rtl;\n")
      (vhdl-mode)
      (display-buffer buffer))))

(defun vhdl-blockdiag-save-vhdl (filename)
  "Generate VHDL and save it to FILENAME."
  (interactive "FSave VHDL to: ")
  (vhdl-blockdiag-generate-vhdl)
  (with-current-buffer "*vhdl-blockdiag-vhdl*"
    (write-file filename)))

;;; Minor Mode

(defvar vhdl-blockdiag-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'vhdl-blockdiag-render-svg)
    (define-key map (kbd "C-c C-v") #'vhdl-blockdiag-generate-vhdl)
    (define-key map (kbd "C-c C-s") #'vhdl-blockdiag-save-vhdl)
    map)
  "Keymap for `vhdl-blockdiag-mode'.")

;;;###autoload
(define-minor-mode vhdl-blockdiag-mode
  "Minor mode for VHDL Block Diagram DSL files."
  :lighter " VBD"
  :keymap vhdl-blockdiag-mode-map)

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.vbd\\'" . emacs-lisp-mode))
;;;###autoload
(add-hook 'emacs-lisp-mode-hook (lambda () (when (string-match-p "\\.vbd\\'" (or (buffer-file-name) "")) (vhdl-blockdiag-mode 1))))


(provide 'vhdl-blockdiag)
;;; vhdl-blockdiag.el ends here
