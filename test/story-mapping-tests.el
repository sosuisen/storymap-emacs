;;; story-mapping-tests.el --- Tests of story-mapping -*- lexical-binding: t; -*-

;;; Commentary:

;; The tests run the real render program, so build it first:
;;
;;   cargo build --release
;;   emacs -Q --batch -L . -l test/story-mapping-tests.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'ert-x)
(require 'cl-lib)
(require 'story-mapping)

(defmacro story-mapping-tests--with-source (spec &rest body)
  "Run BODY in a buffer that visits a temporary file.
SPEC is (DIRECTORY-VARIABLE FILE-NAME TEXT).  BODY sees the directory of the
file in DIRECTORY-VARIABLE, and the update delay is zero."
  (declare (indent 1))
  (let ((buffer (make-symbol "buffer")))
    `(let* ((,(nth 0 spec) (file-name-as-directory (make-temp-file "story-mapping" t)))
            (story-mapping-update-delay 0)
            (,buffer (find-file-noselect (expand-file-name ,(nth 1 spec) ,(nth 0 spec)))))
       (unwind-protect
           (with-current-buffer ,buffer
             (insert ,(nth 2 spec))
             ,@body)
         (with-current-buffer ,buffer (set-buffer-modified-p nil))
         (kill-buffer ,buffer)
         (delete-directory ,(nth 0 spec) t)))))

(defun story-mapping-tests--wait ()
  "Wait until the current source buffer has no scheduled or running render."
  (with-timeout (30 (error "The render did not end"))
    (while (or story-mapping--timer story-mapping--process)
      (accept-process-output nil 0.01))))

(defun story-mapping-tests--image ()
  "Return the image data that the preview of the current buffer shows."
  (with-current-buffer story-mapping--preview
    (plist-get (cdr (get-text-property (point-min) 'display)) :data)))

(defun story-mapping-tests--png-width (png)
  "Return the width of the image data PNG."
  (cl-reduce (lambda (width byte) (+ (* width 256) byte))
             (substring png 16 20)
             :initial-value 0))

(defun story-mapping-tests--direct-png (outline)
  "Return the image of OUTLINE that the program writes without the preview."
  (let ((coding-system-for-read 'binary)
        (coding-system-for-write 'utf-8-unix))
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (call-process-region outline nil (story-mapping--program) nil t nil "png" "1")
      (buffer-string))))

(defun story-mapping-tests--file-text (file)
  "Return the text of FILE, decoded as UTF-8."
  (let ((coding-system-for-read 'utf-8-unix))
    (with-temp-buffer
      (insert-file-contents file)
      (buffer-string))))

;;; Opening the preview

(ert-deftest story-mapping-rejects-file-that-is-not-markdown ()
  "`.md'でないファイルでは、エラーになり、プレビューは開かない。"
  (story-mapping-tests--with-source (dir "note.txt" "- A\n")
    (should-error (story-mapping) :type 'user-error)
    (should-not story-mapping--preview)))

(ert-deftest story-mapping-rejects-buffer-without-file ()
  "ファイルのないバッファでは、エラーになる。"
  (with-temp-buffer
    (should-error (story-mapping) :type 'user-error)))

(ert-deftest story-mapping-accepts-upper-case-extension ()
  "拡張子の`.MD'も受け付ける。"
  (story-mapping-tests--with-source (dir "NOTE.MD" "- A\n")
    (story-mapping)
    (story-mapping-tests--wait)
    (should story-mapping--preview)))

(ert-deftest story-mapping-reports-missing-program ()
  "描画プログラムがないと、エラーになり、プレビューは開かない。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n")
    (let ((story-mapping-program "no-such-story-mapping-program"))
      (should-error (story-mapping) :type 'user-error))
    (should-not story-mapping--preview)))

(ert-deftest story-mapping-opens-panel-on-the-right ()
  "プレビューは右のパネルに開き、選択中のウィンドウは元のバッファのままである。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n")
    (let ((source-window (selected-window)))
      (set-window-buffer source-window (current-buffer))
      (story-mapping)
      (story-mapping-tests--wait)
      (let ((window (get-buffer-window story-mapping--preview)))
        (should (eq (window-parameter window 'window-side) 'right))
        (should (eq (selected-window) source-window))))))

(ert-deftest story-mapping-shows-the-map-of-the-buffer-text ()
  "プレビューは、保存前のバッファの内容（日本語を含む）を描いたPNGを表示する。"
  (story-mapping-tests--with-source (dir "map.md" "- 活動A\n  - タスク1\n")
    (story-mapping)
    (story-mapping-tests--wait)
    (should (equal (story-mapping-tests--image)
                   (story-mapping-tests--direct-png (buffer-string))))))

(ert-deftest story-mapping-reads-the-whole-narrowed-buffer ()
  "ナロイング中でも、バッファ全体を描く。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n- B\n")
    (narrow-to-region (point-min) 3)
    (story-mapping)
    (story-mapping-tests--wait)
    (should (equal (story-mapping-tests--image)
                   (story-mapping-tests--direct-png "- A\n- B\n")))))

(ert-deftest story-mapping-reuses-the-preview ()
  "もう一度呼んでも、プレビューのバッファとパネルは増えない。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n")
    (story-mapping)
    (story-mapping-tests--wait)
    (let ((preview story-mapping--preview)
          (windows (window-list)))
      (story-mapping)
      (story-mapping-tests--wait)
      (should (eq story-mapping--preview preview))
      (should (= (length (window-list)) (length windows))))))

;;; Following the edits

(ert-deftest story-mapping-follows-edits ()
  "編集すると、プレビューは編集後の内容に更新される。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n")
    (story-mapping)
    (story-mapping-tests--wait)
    (insert "- B\n")
    (story-mapping-tests--wait)
    (should (equal (story-mapping-tests--image)
                   (story-mapping-tests--direct-png "- A\n- B\n")))))

(ert-deftest story-mapping-renders-again-after-edit-during-render ()
  "描画中の編集は、その描画の後で反映される。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n")
    (story-mapping)
    (should (process-live-p story-mapping--process))
    (insert "- B\n")
    (story-mapping--update (current-buffer))
    (should story-mapping--render-again)
    (story-mapping-tests--wait)
    (should (equal (story-mapping-tests--image)
                   (story-mapping-tests--direct-png "- A\n- B\n")))))

(ert-deftest story-mapping-survives-a-major-mode-change ()
  "メジャーモードを変えても、編集に追従する。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n")
    (story-mapping)
    (story-mapping-tests--wait)
    (text-mode)
    ;; Emacs loads the new value of the hook when the buffer changes.  In real
    ;; use the command loop does this, so that the next edit runs the hook.
    (with-temp-buffer)
    (insert "- B\n")
    (story-mapping-tests--wait)
    (should (equal (story-mapping-tests--image)
                   (story-mapping-tests--direct-png "- A\n- B\n")))))

(ert-deftest story-mapping-does-not-render-hidden-preview ()
  "パネルが閉じられている間は、編集しても描画しない。再び開くと最新の内容を表示する。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n")
    (story-mapping)
    (story-mapping-tests--wait)
    (let ((old-image (story-mapping-tests--image)))
      (delete-window (get-buffer-window story-mapping--preview))
      (insert "- B\n")
      (story-mapping-tests--wait)
      (should (equal (story-mapping-tests--image) old-image))
      (story-mapping)
      (story-mapping-tests--wait)
      (should (equal (story-mapping-tests--image)
                     (story-mapping-tests--direct-png "- A\n- B\n"))))))

(ert-deftest story-mapping-keeps-last-image-when-render-fails ()
  "描画に失敗すると、前の画像を残し、理由をメッセージで伝える。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n")
    (story-mapping)
    (story-mapping-tests--wait)
    (let ((old-image (story-mapping-tests--image))
          (story-mapping-scale -1)
          (messages nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (&rest args) (push (apply #'format args) messages))))
        (story-mapping--render (current-buffer))
        (story-mapping-tests--wait))
      (should (equal (story-mapping-tests--image) old-image))
      (should (string-match-p "scale must be a positive" (car messages))))))

;;; Zoom

(ert-deftest story-mapping-zoom-changes-the-image-and-the-mode-line ()
  "ズームすると、画像の大きさとモードラインの倍率が変わる。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n")
    (story-mapping)
    (story-mapping-tests--wait)
    (let ((width (story-mapping-tests--png-width (story-mapping-tests--image))))
      (with-current-buffer story-mapping--preview
        (story-mapping--apply-zoom 200)
        (should (equal mode-name "StoryMap 200%")))
      (story-mapping-tests--wait)
      (should (<= (abs (- (story-mapping-tests--png-width (story-mapping-tests--image))
                          (* 2 width)))
                  1)))))

(ert-deftest story-mapping-zoom-stays-between-the-limits ()
  "ズームは20%から200%の範囲に収まり、リセットで100%に戻る。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n")
    (story-mapping)
    (story-mapping-tests--wait)
    (let ((source (current-buffer)))
      (with-current-buffer story-mapping--preview
        (setq story-mapping--zoom 200)
        (story-mapping-zoom-in)
        (should (= story-mapping--zoom 200))
        (setq story-mapping--zoom 20)
        (story-mapping-zoom-out)
        (should (= story-mapping--zoom 20))
        (story-mapping-zoom-reset)
        (should (= story-mapping--zoom 100))
        (with-current-buffer source (story-mapping-tests--wait))))))

;;; Closing

(ert-deftest story-mapping-quit-closes-the-panel-and-stops-following ()
  "パネルを閉じると、プレビューのバッファが消え、編集に追従しなくなる。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n")
    (story-mapping)
    (story-mapping-tests--wait)
    (let ((preview story-mapping--preview)
          (source (current-buffer)))
      (with-selected-window (get-buffer-window preview)
        (story-mapping-quit))
      (with-current-buffer source
        (should-not (buffer-live-p preview))
        (should-not story-mapping--preview)
        (insert "- B\n")
        (should-not story-mapping--timer)))))

(ert-deftest story-mapping-kills-preview-with-the-source ()
  "元のバッファを消すと、プレビューのバッファも消える。"
  (let* ((story-mapping-update-delay 0)
         (dir (file-name-as-directory (make-temp-file "story-mapping" t)))
         (source (find-file-noselect (expand-file-name "map.md" dir)))
         preview)
    (unwind-protect
        (progn
          (with-current-buffer source
            (insert "- A\n")
            (story-mapping)
            (setq preview story-mapping--preview)
            (set-buffer-modified-p nil))
          (kill-buffer source)
          (should-not (buffer-live-p preview)))
      (delete-directory dir t))))

;;; Export

(ert-deftest story-mapping-export-writes-the-unsaved-text-as-utf8 ()
  "SVGの出力は、保存前のバッファの内容をUTF-8で指定のファイルへ書く。"
  (story-mapping-tests--with-source (dir "map.md" "- 活動A\n")
    (let ((file (expand-file-name "out.svg" dir)))
      (story-mapping-export-svg file)
      (let ((svg (story-mapping-tests--file-text file)))
        (should (string-prefix-p "<svg" svg))
        (should (string-search "活動A" svg))))))

(ert-deftest story-mapping-export-default-is-next-to-the-markdown-file ()
  "SVGの保存先を聞かれてRETを押すと、`.md'の隣の同名の`.svg'へ出力する。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n")
    (ert-simulate-keys (kbd "RET")
      (call-interactively #'story-mapping-export-svg))
    (should (file-exists-p (expand-file-name "map.svg" dir)))))

(ert-deftest story-mapping-export-works-in-the-preview ()
  "プレビューのバッファからもSVGを出力でき、既定の保存先は`.md'の隣である。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n")
    (story-mapping)
    (story-mapping-tests--wait)
    (with-current-buffer story-mapping--preview
      (ert-simulate-keys (kbd "RET")
        (call-interactively #'story-mapping-export-svg)))
    (should (file-exists-p (expand-file-name "map.svg" dir)))))

(ert-deftest story-mapping-export-to-directory-uses-the-default-name ()
  "保存先にフォルダを指定すると、その中の同名の`.svg'へ出力する。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n")
    (let ((sub (expand-file-name "sub/" dir)))
      (make-directory sub)
      (ert-simulate-keys (vconcat (kbd "sub/") (kbd "RET"))
        (call-interactively #'story-mapping-export-svg))
      (should (file-exists-p (expand-file-name "map.svg" sub))))))

(ert-deftest story-mapping-export-asks-before-replacing ()
  "同名のファイルがあれば確認し、断ると内容を変えない。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n")
    (let ((file (expand-file-name "map.svg" dir)))
      (write-region "old" nil file)
      (should-error
       ;; In batch mode, `y-or-n-p' reads a whole line
       (ert-simulate-keys (vconcat (kbd "RET") "n" (kbd "RET"))
         (call-interactively #'story-mapping-export-svg))
       :type 'user-error)
      (should (equal (story-mapping-tests--file-text file) "old")))))

(ert-deftest story-mapping-export-replaces-after-confirmation ()
  "確認に同意すると、同名のファイルを置き換える。"
  (story-mapping-tests--with-source (dir "map.md" "- A\n")
    (let ((file (expand-file-name "map.svg" dir)))
      (write-region "old" nil file)
      (ert-simulate-keys (vconcat (kbd "RET") "y" (kbd "RET"))
        (call-interactively #'story-mapping-export-svg))
      (should (string-prefix-p "<svg" (story-mapping-tests--file-text file))))))

(ert-deftest story-mapping-export-rejects-file-that-is-not-markdown ()
  "`.md'でないファイルでは、SVGの出力もエラーになる。"
  (story-mapping-tests--with-source (dir "note.txt" "- A\n")
    (should-error (call-interactively #'story-mapping-export-svg) :type 'user-error)))

(provide 'story-mapping-tests)

;;; story-mapping-tests.el ends here
