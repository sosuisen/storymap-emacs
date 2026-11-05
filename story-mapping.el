;;; story-mapping.el --- Preview a Markdown outline as a user story map -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Hidekazu Kubota

;; Author: Hidekazu Kubota
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools, outlines
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; `M-x story-mapping' opens a panel on the right that shows the Markdown
;; outline of the current buffer as a user story map.  The panel follows
;; your edits.
;;
;; `M-x story-mapping-export-svg' saves the map as an SVG file.
;;
;; The Rust program `story-mapping-render' draws the map.  Build it with
;; `cargo build --release' in the directory of this file, or install it
;; with `cargo install --path .'.

;;; Code:

(require 'image-mode)
(require 'subr-x)

(defgroup story-mapping nil
  "Preview a Markdown outline as a user story map."
  :group 'tools
  :prefix "story-mapping-")

(defcustom story-mapping-program "story-mapping-render"
  "The program that renders the map.
This is a file name or a command in the directories of the variable
`exec-path'.  If it is not found, the directory target/release next to
this library is also searched."
  :type 'string)

(defcustom story-mapping-window-width 0.5
  "The width of the preview panel, as a fraction of the frame width."
  :type 'float)

(defcustom story-mapping-update-delay 0.3
  "The seconds to wait after an edit before the preview is updated."
  :type 'number)

(defcustom story-mapping-scale 1.0
  "The image pixels per map pixel when the zoom level is 100%.
Use a larger value on a high resolution display."
  :type 'number)

(defconst story-mapping--directory
  (file-name-directory (or load-file-name buffer-file-name))
  "The directory of this library.")

(defconst story-mapping--zoom-min 20 "The lowest zoom level in percent.")
(defconst story-mapping--zoom-max 200 "The highest zoom level in percent.")
(defconst story-mapping--zoom-step 10 "The zoom change per key press in percent.")

;; The state of a source buffer.  It must survive `revert-buffer' and a change
;; of the major mode.  Both kill the local variables and the local hooks, and
;; then the preview would stop following the edits without any notice.
(defvar-local story-mapping--preview nil "The preview buffer of this source buffer.")
(defvar-local story-mapping--timer nil "The timer of the next update.")
(defvar-local story-mapping--process nil "The render process that is running.")
(defvar-local story-mapping--render-again nil
  "Non-nil if the outline changed while the render process was running.")
(dolist (variable '(story-mapping--preview story-mapping--timer
                    story-mapping--process story-mapping--render-again))
  (put variable 'permanent-local t))

;; The state of a preview buffer
(defvar-local story-mapping--source nil "The source buffer of this preview buffer.")
(defvar-local story-mapping--zoom 100 "The zoom level of this preview in percent.")

;;; Finding the input and the program

(defun story-mapping--source-buffer ()
  "Return the source buffer for a command called in the current buffer."
  (or story-mapping--source (current-buffer)))

(defun story-mapping--check-markdown-file (buffer)
  "Signal an error unless BUFFER visits a Markdown file."
  (let ((file (buffer-file-name buffer))
        (case-fold-search t))
    (unless (and file (string-match-p "\\.md\\'" file))
      (user-error "Not a Markdown file (.md): %s" (buffer-name buffer)))))

(defun story-mapping--program ()
  "Return the file name of the render program, or signal an error."
  (or (executable-find story-mapping-program)
      (locate-file story-mapping-program
                   (list (expand-file-name "target/release" story-mapping--directory))
                   exec-suffixes
                   #'file-executable-p)
      (user-error "Cannot find %s.  Run `cargo build --release' in %s"
                  story-mapping-program story-mapping--directory)))

(defun story-mapping--outline (source)
  "Return all the text of the buffer SOURCE, even when it is narrowed."
  (with-current-buffer source
    (save-restriction
      (widen)
      (buffer-substring-no-properties (point-min) (point-max)))))

;;; Rendering the preview

(defun story-mapping--png-arguments (preview)
  "Return the program arguments for the image of the buffer PREVIEW."
  (list "png"
        (number-to-string
         (* story-mapping-scale
            (/ (buffer-local-value 'story-mapping--zoom preview) 100.0)))))

(defun story-mapping--show-image (preview png)
  "Show the image data PNG in the buffer PREVIEW."
  (with-current-buffer preview
    (with-silent-modifications
      (when (= (point-min) (point-max))
        (insert " ")
        (goto-char (point-min)))
      ;; Change only the property of the text.  Replacing the text would move
      ;; the window to the top of the map at each update.
      (put-text-property (point-min) (point-max) 'display
                         ;; `:scale 1' keeps the pixels sharp.  By default, Emacs
                         ;; may enlarge an image to match the size of the font.
                         (create-image png 'png t :scale 1)))))

(defun story-mapping--finish-render (source process)
  "Handle the end of the render PROCESS of the buffer SOURCE."
  (let ((output (process-buffer process)))
    (unwind-protect
        (when (buffer-live-p source)
          (with-current-buffer source
            ;; A process that was stopped is not the current one any more
            (when (eq process story-mapping--process)
              (setq story-mapping--process nil)
              (let ((data (with-current-buffer output (buffer-string))))
                (if (zerop (process-exit-status process))
                    (story-mapping--show-image story-mapping--preview data)
                  ;; Keep the last good image, so that the map does not flicker
                  (message "story-mapping: %s"
                           (string-trim (decode-coding-string data 'utf-8)))))
              (when story-mapping--render-again
                (story-mapping--render source)))))
      (kill-buffer output))))

(defun story-mapping--start-process (source)
  "Start a process that renders the buffer SOURCE, and return it.
The process waits for the outline on its standard input."
  (let ((program (story-mapping--program))
        (arguments (story-mapping--png-arguments
                    (buffer-local-value 'story-mapping--preview source)))
        (output (generate-new-buffer " *story-mapping-output*" t))
        ;; Not the directory of the file.  It may be on a remote host, and on
        ;; Windows a running program blocks the deletion of its directory.
        (default-directory story-mapping--directory))
    (with-current-buffer output (set-buffer-multibyte nil))
    ;; Standard error goes to the same buffer.  The program writes there only
    ;; when it fails, and then it writes no image.
    (make-process
     :name "story-mapping-render"
     :buffer output
     :command (cons program arguments)
     :connection-type 'pipe
     :coding '(binary . utf-8-unix)
     :noquery t
     :sentinel (lambda (process _event)
                 (unless (process-live-p process)
                   (story-mapping--finish-render source process))))))

(defun story-mapping--render (source)
  "Render the buffer SOURCE, or again after the render that is running."
  (with-current-buffer source
    (if (process-live-p story-mapping--process)
        (setq story-mapping--render-again t)
      (setq story-mapping--render-again nil)
      ;; Remember the process before sending the outline.  Sending may run the
      ;; sentinel, which ignores any process but the remembered one.
      (let ((process (story-mapping--start-process source)))
        (setq story-mapping--process process)
        (process-send-string process (story-mapping--outline source))
        (process-send-eof process)))))

(defun story-mapping--update (source)
  "Render the buffer SOURCE if its preview is visible."
  (when (buffer-live-p source)
    (with-current-buffer source
      (setq story-mapping--timer nil)
      (when (and story-mapping--preview
                 (get-buffer-window story-mapping--preview t))
        (story-mapping--render source)))))

(defun story-mapping--schedule-update (&rest _)
  "Update the preview of the current buffer after a pause in the editing."
  (when story-mapping--timer
    (cancel-timer story-mapping--timer))
  (setq story-mapping--timer
        (run-with-timer story-mapping-update-delay nil
                        #'story-mapping--update (current-buffer))))
(put 'story-mapping--schedule-update 'permanent-local-hook t)

;;; The link between the source buffer and the preview buffer

(defun story-mapping--stop (source)
  "Stop following the edits of the buffer SOURCE."
  (with-current-buffer source
    (when story-mapping--timer
      (cancel-timer story-mapping--timer))
    (let ((process story-mapping--process))
      (setq story-mapping--timer nil
            story-mapping--process nil
            story-mapping--render-again nil
            story-mapping--preview nil)
      (when process
        (delete-process process)))
    (remove-hook 'after-change-functions #'story-mapping--schedule-update t)
    (remove-hook 'kill-buffer-hook #'story-mapping--kill-preview t)))

(defun story-mapping--kill-preview ()
  "Kill the preview buffer of the current buffer."
  (when story-mapping--preview
    (kill-buffer story-mapping--preview)))
(put 'story-mapping--kill-preview 'permanent-local-hook t)

(defun story-mapping--preview-killed ()
  "Stop the updates when the current preview buffer is killed."
  (when (buffer-live-p story-mapping--source)
    (story-mapping--stop story-mapping--source)))

(defun story-mapping--create-preview (source)
  "Create and return the preview buffer of the buffer SOURCE."
  (let ((preview (generate-new-buffer
                  (format "*Story Map: %s*" (buffer-name source)))))
    (with-current-buffer preview
      (story-mapping-preview-mode)
      (setq story-mapping--source source)
      (add-hook 'kill-buffer-hook #'story-mapping--preview-killed nil t))
    (with-current-buffer source
      (setq story-mapping--preview preview)
      (add-hook 'after-change-functions #'story-mapping--schedule-update nil t)
      (add-hook 'kill-buffer-hook #'story-mapping--kill-preview nil t))
    preview))

;;; The preview mode

(defun story-mapping--apply-zoom (percent)
  "Set the zoom level of the current preview to PERCENT and render it."
  (setq story-mapping--zoom
        (max story-mapping--zoom-min (min story-mapping--zoom-max percent)))
  (setq mode-name (format "StoryMap %d%%" story-mapping--zoom))
  (force-mode-line-update)
  ;; The end of the mode line is often cut off in a narrow panel
  (message "Zoom: %d%%" story-mapping--zoom)
  (story-mapping--render story-mapping--source))

(defun story-mapping-zoom-in ()
  "Make the map in the preview larger."
  (interactive nil story-mapping-preview-mode)
  (story-mapping--apply-zoom (+ story-mapping--zoom story-mapping--zoom-step)))

(defun story-mapping-zoom-out ()
  "Make the map in the preview smaller."
  (interactive nil story-mapping-preview-mode)
  (story-mapping--apply-zoom (- story-mapping--zoom story-mapping--zoom-step)))

(defun story-mapping-zoom-reset ()
  "Show the map in the preview at 100%."
  (interactive nil story-mapping-preview-mode)
  (story-mapping--apply-zoom 100))

(defun story-mapping-quit ()
  "Close the preview and stop following the edits."
  (interactive nil story-mapping-preview-mode)
  (quit-window t))

(defun story-mapping--revert-preview (&rest _)
  "Render the map of the current preview again."
  (story-mapping--render story-mapping--source))

(defvar-keymap story-mapping-preview-mode-map
  "+" #'story-mapping-zoom-in
  "=" #'story-mapping-zoom-in
  "-" #'story-mapping-zoom-out
  "0" #'story-mapping-zoom-reset
  "q" #'story-mapping-quit
  ;; A map is one large image on one line.  The ordinary movement commands
  ;; cannot scroll inside it, so use the commands of `image-mode'.
  "<remap> <forward-char>" #'image-forward-hscroll
  "<remap> <right-char>" #'image-forward-hscroll
  "<remap> <backward-char>" #'image-backward-hscroll
  "<remap> <left-char>" #'image-backward-hscroll
  "<remap> <next-line>" #'image-next-line
  "<remap> <previous-line>" #'image-previous-line
  "<remap> <scroll-up-command>" #'image-scroll-up
  "<remap> <scroll-down-command>" #'image-scroll-down
  "<remap> <scroll-left>" #'image-scroll-left
  "<remap> <scroll-right>" #'image-scroll-right
  "<remap> <move-beginning-of-line>" #'image-bol
  "<remap> <move-end-of-line>" #'image-eol
  "<remap> <beginning-of-buffer>" #'image-bob
  "<remap> <end-of-buffer>" #'image-eob)

(define-derived-mode story-mapping-preview-mode special-mode "StoryMap 100%"
  "Major mode of the panel that shows a story map.

\\{story-mapping-preview-mode-map}"
  (setq-local cursor-type nil
              truncate-lines t
              ;; Otherwise Emacs scrolls back to show the point after each scroll
              auto-hscroll-mode nil
              revert-buffer-function #'story-mapping--revert-preview
              mwheel-scroll-up-function #'image-scroll-up
              mwheel-scroll-down-function #'image-scroll-down
              mwheel-scroll-left-function #'image-scroll-left
              mwheel-scroll-right-function #'image-scroll-right)
  (image-mode-setup-winprops))

;;; Commands

;;;###autoload
(defun story-mapping ()
  "Show the story map of the current Markdown file in a panel on the right.
The map follows the edits of the buffer, also before they are saved.

In the panel, + and - change the zoom level, 0 resets it, q closes the
panel, and the arrow keys scroll the map."
  (interactive)
  (let ((source (story-mapping--source-buffer)))
    (story-mapping--check-markdown-file source)
    (story-mapping--program)
    (let ((preview (or (buffer-local-value 'story-mapping--preview source)
                       (story-mapping--create-preview source))))
      (display-buffer preview
                      `((display-buffer-reuse-window display-buffer-in-side-window)
                        (side . right)
                        (window-width . ,story-mapping-window-width)))
      (story-mapping--render source))))

(defun story-mapping--svg-file-name (markdown-file)
  "Return the name of the SVG file next to MARKDOWN-FILE."
  (concat (file-name-sans-extension markdown-file) ".svg"))

(defun story-mapping--read-svg-file (default)
  "Ask where to save the SVG file, and return the file name.
Pressing RET selects DEFAULT.  Ask before replacing an existing file."
  (let* ((default-name (file-name-nondirectory default))
         (answer (read-file-name
                  (format-prompt "Export SVG to" default-name)
                  (file-name-directory default) default))
         (file (if (file-directory-p answer)
                   (expand-file-name default-name answer)
                 answer)))
    (when (and (file-exists-p file)
               (not (y-or-n-p (format "%s exists.  Replace it? " file))))
      (user-error "Canceled"))
    file))

;;;###autoload
(defun story-mapping-export-svg (file)
  "Save the story map of the current Markdown buffer to the SVG FILE.
Interactively, ask for the file.  The default is the file with the same
name next to the Markdown file.  Also usable in the preview panel."
  (interactive
   (let ((source (story-mapping--source-buffer)))
     (story-mapping--check-markdown-file source)
     (list (story-mapping--read-svg-file
            (story-mapping--svg-file-name (buffer-file-name source))))))
  (let ((outline (story-mapping--outline (story-mapping--source-buffer)))
        (program (story-mapping--program))
        ;; The file of the buffer may be on a remote host, and the program is local
        (default-directory story-mapping--directory)
        (coding-system-for-read 'utf-8-unix)
        (coding-system-for-write 'utf-8-unix))
    (with-temp-buffer
      ;; Standard error goes to this buffer too.  See `story-mapping--start-process'.
      (unless (eql 0 (call-process-region outline nil program nil t nil "svg"))
        (error "story-mapping: %s" (string-trim (buffer-string))))
      (write-region nil nil file))))

(provide 'story-mapping)

;;; story-mapping.el ends here
