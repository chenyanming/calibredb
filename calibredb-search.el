;;; calibredb-search.el -*- lexical-binding: t; -*-

;; Author: Damon Chan <elecming@gmail.com>

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;; Code:

(require 'calibredb-core)

(eval-when-compile (defvar calibredb-show-entry))
(eval-when-compile (defvar calibredb-show-entry-switch))

(declare-function calibredb-find-file "calibredb-utils.el")
(declare-function calibredb-add "calibredb-utils.el")
(declare-function calibredb-add-dir "calibredb-utils.el")
(declare-function calibredb-clone "calibredb-utils.el")
(declare-function calibredb-remove "calibredb-utils.el")
(declare-function calibredb-library-next "calibredb-library.el")
(declare-function calibredb-library-previous "calibredb-library.el")
(declare-function calibredb-set-metadata-dispatch "calibredb-transient.el")
(declare-function calibredb-find-file-other-frame "calibredb-utils.el")
(declare-function calibredb-open-file-with-default-tool "calibredb-utils.el")
(declare-function calibredb-open-dired "calibredb-utils.el")
(declare-function calibredb-catalog-bib-dispatch "calibredb-transient.el")
(declare-function calibredb-export-dispatch "calibredb-transient.el")
(declare-function calibredb-edit-annotation "calibredb-annotation.el")
(declare-function calibredb-set-metadata--tags "calibredb-utils.el")
(declare-function calibredb-set-metadata--author_sort "calibredb-utils.el")
(declare-function calibredb-set-metadata--authors "calibredb-utils.el")
(declare-function calibredb-set-metadata--title "calibredb-utils.el")
(declare-function calibredb-set-metadata--comments "calibredb-utils.el")
(declare-function calibredb-edit-annotation-header "calibredb-annotation.el")
(declare-function calibredb-show--buffer-name "calibredb-show.el")
(declare-function calibredb-insert-image "calibredb-utils.el")
(declare-function calibredb-show-mode "calibredb-show.el")
(declare-function calibredb-find-marked-candidates "calibredb-utils.el")
(declare-function calibredb-read-metadatas "calibredb-utils.el")
(declare-function calibredb-find-candidate-at-point "calibredb-utils.el")
(declare-function calibredb-show-refresh "calibredb-show.el")

(defcustom calibredb-search-filter ""
  "Query string filtering shown entries."
  :group 'calibredb
  :type 'string)

(defvar calibredb-full-entries nil
  "List of the all entries currently on library.")

(defvar calibredb-search-entries nil
  "List of the entries currently on display.")

(defvar calibredb-search-filter-active nil
  "When non-nil, calibredb is currently reading a filter from the minibuffer.
When live editing the filter, it is bound to :live.")

(defvar calibredb-search-last-update 0
  "The last time the buffer was redrawn in epoch seconds.")

(defvar calibredb-search-print-entry-function #'calibredb-search-print-entry--default
  "Function to print entries into the *calibredb-search* buffer.")

(defvar calibredb-search-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-3] #'calibredb-search-mouse)
    (define-key map (kbd "<RET>") #'calibredb-find-file)
    (define-key map "?" #'calibredb-dispatch)
    (define-key map "a" #'calibredb-add)
    (define-key map "A" #'calibredb-add-dir)
    (define-key map "c" #'calibredb-clone)
    (define-key map "d" #'calibredb-remove)
    (define-key map "j" #'calibredb-next-entry)
    (define-key map "k" #'calibredb-previous-entry)
    (define-key map "l" #'calibredb-library-list)
    (define-key map "n" #'calibredb-library-next)
    (define-key map "p" #'calibredb-library-previous)
    (define-key map "s" #'calibredb-set-metadata-dispatch)
    (define-key map "S" #'calibredb-switch-library)
    (define-key map "o" #'calibredb-find-file)
    (define-key map "O" #'calibredb-find-file-other-frame)
    (define-key map "v" #'calibredb-view)
    (define-key map "V" #'calibredb-open-file-with-default-tool)
    (define-key map "." #'calibredb-open-dired)
    (define-key map "b" #'calibredb-catalog-bib-dispatch)
    (define-key map "e" #'calibredb-export-dispatch)
    (define-key map "r" #'calibredb-search-refresh-and-clear-filter)
    (define-key map "R" #'calibredb-search-refresh-or-resume)
    (define-key map "q" #'calibredb-search-quit)
    (define-key map "m" #'calibredb-mark-and-forward)
    (define-key map "f" #'calibredb-toggle-favorite-at-point)
    (define-key map "x" #'calibredb-toggle-archive-at-point)
    (define-key map "h" #'calibredb-toggle-highlight-at-point)
    (define-key map "u" #'calibredb-unmark-and-forward)
    (define-key map "i" #'calibredb-edit-annotation)
    (define-key map (kbd "<DEL>") #'calibredb-unmark-and-backward)
    (define-key map (kbd "<backtab>") #'calibredb-toggle-view)
    (define-key map (kbd "TAB") #'calibredb-toggle-view-at-point)
    (define-key map "\M-n" #'calibredb-show-next-entry)
    (define-key map "\M-p" #'calibredb-show-previous-entry)
    (define-key map "/" #'calibredb-search-live-filter)
    (define-key map "\M-t" #'calibredb-set-metadata--tags)
    (define-key map "\M-a" #'calibredb-set-metadata--author_sort)
    (define-key map "\M-A" #'calibredb-set-metadata--authors)
    (define-key map "\M-T" #'calibredb-set-metadata--title)
    (define-key map "\M-c" #'calibredb-set-metadata--comments)
    map)
  "Keymap for `calibredb-search-mode'.")

(defvar calibredb-edit-annotation-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\C-c\C-c" 'calibredb-send-edited-annotation)
    (define-key map "\C-c\C-k" 'calibredb-annotation-quit)
    map)
  "Keymap for `calibredb-edit-annotation-mode'.")

(defvar calibredb-search-header-function #'calibredb-search-header
  "Function that returns the string to be used for the Calibredb search header.")

(defvar calibredb-images-path (concat (file-name-directory load-file-name) "img")
  "Relative path to images.")

(defcustom calibredb-search-unique-buffers nil
  "TODO: When non-nil, every entry buffer gets a unique name.
This allows for displaying multiple serch buffers at the same
time."
  :group 'calibredb
  :type 'boolean)

(define-obsolete-function-alias 'calibredb-search-ret
  'calibredb-view "calibredb 2.0.0")

(defcustom calibredb-detial-view nil
  "Set Non-nil to change detail view, nil to compact view - *calibredb-search*."
  :group 'calibredb
  :type 'boolean)

(defcustom calibredb-detial-view-image-show t
  "Set Non-nil to show images in detail view - *calibredb-search*."
  :group 'calibredb
  :type 'boolean)

(defcustom calibredb-detail-view-image-max-width 150
  "Max Width for images in detail view - *calibredb-search*."
  :group 'calibredb
  :type 'integer)

(defcustom calibredb-detail-view-image-max-height 150
  "Max height for images in detail view - *calibredb-search*."
  :group 'calibredb
  :type 'integer)

(defcustom calibredb-list-view-image-max-width 500
  "Max Width for images in list view - *calibredb-list*."
  :group 'calibredb
  :type 'integer)

(defcustom calibredb-list-view-image-max-height 500
  "Max height for images in list view - *calibredb-list*."
  :group 'calibredb
  :type 'integer)

(defun calibredb-search--buffer-name ()
  "Return the appropriate buffer name for ENTRY.
The result depends on the value of `calibredb-search-unique-buffers'."
  (if calibredb-search-unique-buffers
      (format "*calibredb-search-<%s>*" calibredb-root-dir)
    "*calibredb-search*"))

(defun calibredb-show-entry (entry &optional switch)
  "Display ENTRY in the current buffer.
Optional argument SWITCH to switch to *calibredb-search* buffer to other window."
  (unless (eq major-mode 'calibredb-show-mode)
      (when (get-buffer (calibredb-show--buffer-name entry))
        (kill-buffer (calibredb-show--buffer-name entry))))
  (let* ((buff (get-buffer-create (calibredb-show--buffer-name entry)))
         (id (calibredb-getattr entry :id)) ; only get the id
         (tag (calibredb-getattr entry :tag))
         (comment (calibredb-getattr entry :comment))
         (author-sort (calibredb-getattr entry :author-sort))
         (title (calibredb-getattr entry :book-title))
         (pubdate (calibredb-getattr entry :book-pubdate))
         ;; (query-result (cdr (car (calibredb-candidate id)))) ; get the new entry through SQL query
         (file (calibredb-getattr entry :file-path))
         (cover (concat (file-name-directory file) "cover.jpg"))
         (format (calibredb-getattr entry :book-format))
         (original (point))
         beg end)
    (let ((inhibit-read-only t))
      (with-current-buffer buff
        (erase-buffer)
        (setq beg (point))
        ;; (insert (propertize (calibredb-show-metadata entry) 'calibredb-entry entry))
        (insert (format "ID          %s\n" (propertize id 'face 'calibredb-id-face)))
        (setq end (point))
        (put-text-property beg end 'calibredb-entry entry)
        (insert (format "Title       %s\n" (propertize title 'face 'calibredb-title-face)))
        (insert (format "Author_sort %s\n" (propertize author-sort 'face 'calibredb-author-face)))
        (insert (format "Tags        %s\n" (propertize tag 'face 'calibredb-tag-face)))
        (insert (format "Comments    %s\n" (propertize comment 'face 'calibredb-comment-face)))
        (insert (format "Published   %s\n" (propertize pubdate 'face 'calibredb-pubdate-face)))
        (insert (format "File        %s\n" (propertize file 'face 'calibredb-file-face)))
        (insert "\n")
        (if (image-type-available-p (intern format))
            (calibredb-insert-image file "" calibredb-list-view-image-max-width calibredb-list-view-image-max-height)
          (calibredb-insert-image cover "" calibredb-list-view-image-max-width calibredb-list-view-image-max-height))
        ;; (setq end (point))
        (calibredb-show-mode)
        (setq calibredb-show-entry entry)
        (goto-char (point-min))))
    (unless (eq major-mode 'calibredb-show-mode)
      (funcall calibredb-show-entry-switch buff)
      (when switch
        (switch-to-buffer-other-window (set-buffer (calibredb-search--buffer-name)))
        (goto-char original)))))

(defun calibredb-next-entry ()
  "Move to next entry."
  (interactive)
  (let ((ori "") (new ""))
    (while (and (equal new ori) new ori)
      (setq ori (calibredb-getattr (cdr (get-text-property (point) 'calibredb-entry nil)) :id))
      (forward-line 1)
      (setq new (calibredb-getattr (cdr (get-text-property (point) 'calibredb-entry nil)) :id)))))

(defun calibredb-previous-entry ()
  "Move to previous entry."
  (interactive)
  (let ((ori "") (new ""))
    (while (and (equal new ori) new ori (> (line-number-at-pos) 1))
      (forward-line -1)
      (save-excursion
        (setq ori (calibredb-getattr (cdr (get-text-property (point) 'calibredb-entry nil)) :id))
        (forward-line -1)
        (setq new (calibredb-getattr (cdr (get-text-property (point) 'calibredb-entry nil)) :id))))))

(defun calibredb-show-next-entry ()
  "Show next entry."
  (interactive)
  (calibredb-next-entry)
  (calibredb-show-entry (cdr (get-text-property (point) 'calibredb-entry nil)) :switch))

(defun calibredb-show-previous-entry ()
  "Show previous entry."
  (interactive)
  (calibredb-previous-entry)
  (calibredb-show-entry (cdr (get-text-property (point) 'calibredb-entry nil)) :switch))

(defun calibredb-search-buffer ()
  "Create buffer calibredb-search."
  (get-buffer-create "*calibredb-search*"))

(defun calibredb-search-header ()
  "TODO: Return the string to be used as the Calibredb header.
Indicating the library you use."
  (format "Library: %s   %s   %s"
          (propertize calibredb-root-dir 'face font-lock-type-face)
          (concat
           (propertize (format "Total: %s"
                               (if (equal calibredb-search-entries '(""))
                                   "0   "
                                 (concat (number-to-string (length calibredb-search-entries)) "   "))) 'face font-lock-warning-face)
           (propertize (format "%s" (if (equal calibredb-search-filter "")
                                        ""
                                      (concat calibredb-search-filter "   "))) 'face font-lock-keyword-face)
           (propertize (let ((len (length (calibredb-find-marked-candidates))))
                         (if (> len 0)
                             (concat "Marked: " (number-to-string len)) "")) 'face font-lock-negation-char-face))
          (if calibredb-detial-view "< >" "> <")))

(define-derived-mode calibredb-search-mode fundamental-mode "calibredb-search"
  "Major mode for listing calibre entries.
\\{calibredb-search-mode-map}"
  (setq truncate-lines t
        buffer-read-only t
        header-line-format '(:eval (funcall calibredb-search-header-function)))
  (buffer-disable-undo)
  (set (make-local-variable 'hl-line-face) 'calibredb-search-header-highlight-face)
  (hl-line-mode)
  (add-hook 'minibuffer-setup-hook 'calibredb-search--minibuffer-setup))

(defun calibredb-search-mouse (event)
  "Visit the calibredb-entry click on.
Argument EVENT mouse event."
  (interactive "e")
  (let ((window (posn-window (event-end event)))
        (pos (posn-point (event-end event))))
    (if (not (windowp window))
        (error "No ebook chosen"))
    (calibredb-show-entry (cdr (get-text-property pos 'calibredb-entry nil)))
    (select-window window)
    (set-buffer (calibredb-search--buffer-name))
    (goto-char pos)))

(defun calibredb-view ()
  "Visit the calibredb-entry."
  (interactive)
  (calibredb-show-entry (cdr (get-text-property (point) 'calibredb-entry nil)) :switch))

(defun calibredb-search-refresh ()
  "Refresh calibredb."
  (interactive)
  (setq calibredb-search-entries (calibredb-candidates))
  (setq calibredb-full-entries calibredb-search-entries)
  (calibredb))

(defun calibredb-search-refresh-or-resume (&optional begin position)
  "Refresh calibredb or resume the BEGIN point and windows POSITION."
  (interactive)
  (let (beg pos)
    (setq beg (or begin (point)))
    (setq pos (or position (window-start)))
    (if (not (equal calibredb-search-filter ""))
        (progn
          (calibredb-search-refresh)
          (calibredb-search-update :force))
      (calibredb-search-refresh))
    (set-window-start (selected-window) pos)
    (goto-char beg)))

(defun calibredb-search-toggle-view-refresh ()
  "TODO Refresh calibredb when toggle view goto the the same id ebook."
  (interactive)
  (let ((id (calibredb-read-metadatas "id")))
    (if (not (equal calibredb-search-filter ""))
        (progn
          (calibredb-search-refresh)
          (calibredb-search-update :force))
      (calibredb-search-refresh))
    (while (not (equal id (calibredb-read-metadatas "id")))
      (forward-line 1))
    (goto-char (line-beginning-position))
    (recenter)))

(defun calibredb-search-refresh-and-clear-filter ()
  "Refresh calibredb and clear the fitler result."
  (interactive)
  (setq calibredb-search-filter "")
  (calibredb-search-refresh)
  (calibredb-search-update :force))

(defun calibredb-search-quit ()
  "Quit *calibredb-entry* then *calibredb-search*."
  (interactive)
  (when (eq major-mode 'calibredb-search-mode)
    (if (get-buffer "*calibredb-entry*")
        (kill-buffer "*calibredb-entry*")
      (if (get-buffer "*calibredb-search*")
          (kill-buffer "*calibredb-search*")))))

(defun calibredb-mark-at-point ()
  "Mark the current line."
  (interactive)
  (remove-overlays (line-beginning-position) (line-end-position))
  (let* ((beg (line-beginning-position))
         (end (line-end-position))
         (inhibit-read-only t)
         (overlay (make-overlay beg end)))
    (overlay-put overlay 'face 'calibredb-mark-face)
    (put-text-property beg end 'calibredb-mark ?>)))

(defun calibredb-mark-and-forward ()
  "Mark the current line and forward."
  (interactive)
  (calibredb-mark-at-point)
  (calibredb-next-entry))

(defun calibredb-unmark-and-forward ()
  "Unmark the current line and forward."
  (interactive)
  (calibredb-unmark-at-point)
  (calibredb-next-entry))

(defun calibredb-unmark-and-backward ()
  "Unmark the current line and backward."
  (interactive)
  (calibredb-unmark-at-point)
  (calibredb-previous-entry))

(defun calibredb-unmark-at-point ()
  "Unmark the current line."
  (interactive)
  (let* ((beg (line-beginning-position))
         (end (line-end-position))
         (inhibit-read-only t))
    (remove-overlays (line-beginning-position) (line-end-position))
    (remove-text-properties beg end '(calibredb-mark nil))))

(defun calibredb-condense-comments (str)
  "Condense whitespace in STR into a single space."
  (replace-regexp-in-string "[[:space:]\n\r]+" " " str))

(defun calibredb-favorite-mouse-1 (event)
  "Visit the location click on.
Argument EVENT mouse event."
  (interactive "e")
  (let ((window (posn-window (event-end event)))
        (pos (posn-point (event-end event))))
    (if (not (windowp window))
        (error "No favorite chosen"))
    (with-current-buffer (window-buffer window)
      (goto-char pos)
      (calibredb-search-keyword-filter calibredb-favorite-keyword))))

(defun calibredb-tag-mouse-1 (event)
  "Visit the location click on.
Argument EVENT mouse event."
  (interactive "e")
  (let ((window (posn-window (event-end event)))
        (pos (posn-point (event-end event))))
    (if (not (windowp window))
        (error "No favorite chosen"))
    (with-current-buffer (window-buffer window)
      (goto-char pos)
      (calibredb-search-keyword-filter (substring-no-properties (word-at-point))))))

(defun calibredb-author-mouse-1 (event)
  "Visit the location click on.
Argument EVENT mouse event."
  (interactive "e")
  (let ((window (posn-window (event-end event)))
        (pos (posn-point (event-end event))))
    (if (not (windowp window))
        (error "No favorite chosen"))
    (with-current-buffer (window-buffer window)
      (goto-char pos)
      (calibredb-search-keyword-filter (substring-no-properties (word-at-point))))))

(defun calibredb-format-mouse-1 (event)
  "Visit the location click on.
Argument EVENT mouse event."
  (interactive "e")
  (let ((window (posn-window (event-end event)))
        (pos (posn-point (event-end event))))
    (if (not (windowp window))
        (error "No favorite chosen"))
    (with-current-buffer (window-buffer window)
      (goto-char pos)
      (calibredb-search-keyword-filter (substring-no-properties (word-at-point))))))

;; favorite

(defun calibredb-toggle-favorite-at-point (&optional keyword)
  "Toggle favorite the current item.
Argument KEYWORD is the tag keyword."
  (interactive)
  (let ((candidates (calibredb-find-marked-candidates)))
    (unless candidates
      (setq candidates (calibredb-find-candidate-at-point)))
    (dolist (cand candidates)
      (let ((id (calibredb-getattr cand :id))
            (tags (calibredb-read-metadatas "tags" cand)))
        (if (s-contains? calibredb-favorite-keyword tags)
            (calibredb-command :command "set_metadata"
                               :option (format "--field tags:\"%s\"" (s-replace calibredb-favorite-keyword "" tags))
                               :id id
                               :library (format "--library-path \"%s\"" calibredb-root-dir))
          (calibredb-command :command "set_metadata"
                             :option (format "--field tags:\"%s,%s\"" tags (or keyword calibredb-favorite-keyword))
                             :id id
                             :library (format "--library-path \"%s\"" calibredb-root-dir)))
        (cond ((equal major-mode 'calibredb-show-mode)
               (calibredb-show-refresh))
              ((eq major-mode 'calibredb-search-mode)
               (calibredb-search-refresh-or-resume))
              (t nil))))))

;; highlight
(defun calibredb-toggle-highlight-at-point (&optional keyword)
  "Toggle highlight the current item.
Argument KEYWORD is the tag keyword."
  (interactive)
  (let ((candidates (calibredb-find-marked-candidates)))
    (unless candidates
      (setq candidates (calibredb-find-candidate-at-point)))
    (dolist (cand candidates)
      (let ((id (calibredb-getattr cand :id))
            (tags (calibredb-read-metadatas "tags" cand)))
        (if (s-contains? calibredb-highlight-keyword tags)
            (calibredb-command :command "set_metadata"
                               :option (format "--field tags:\"%s\"" (s-replace calibredb-highlight-keyword "" tags))
                               :id id
                               :library (format "--library-path \"%s\"" calibredb-root-dir))
          (calibredb-command :command "set_metadata"
                             :option (format "--field tags:\"%s,%s\"" tags (or keyword calibredb-highlight-keyword))
                             :id id
                             :library (format "--library-path \"%s\"" calibredb-root-dir)))
        (cond ((equal major-mode 'calibredb-show-mode)
               (calibredb-show-refresh))
              ((eq major-mode 'calibredb-search-mode)
               (calibredb-search-refresh-or-resume))
              (t nil))))))
;; archive
(defun calibredb-toggle-archive-at-point (&optional keyword)
  "Toggle archive the current item.
Argument KEYWORD is the tag keyword."
  (interactive)
  (let ((candidates (calibredb-find-marked-candidates)))
    (unless candidates
      (setq candidates (calibredb-find-candidate-at-point)))
    (dolist (cand candidates)
      (let ((id (calibredb-getattr cand :id))
            (tags (calibredb-read-metadatas "tags" cand)))
        (if (s-contains? calibredb-archive-keyword tags)
            (calibredb-command :command "set_metadata"
                               :option (format "--field tags:\"%s\"" (s-replace calibredb-archive-keyword "" tags))
                               :id id
                               :library (format "--library-path \"%s\"" calibredb-root-dir))
          (calibredb-command :command "set_metadata"
                             :option (format "--field tags:\"%s,%s\"" tags (or keyword calibredb-archive-keyword))
                             :id id
                             :library (format "--library-path \"%s\"" calibredb-root-dir)))
        (cond ((equal major-mode 'calibredb-show-mode)
               (calibredb-show-refresh))
              ((eq major-mode 'calibredb-search-mode)
               (calibredb-search-refresh-or-resume))
              (t nil))))))

;; live filtering

(defun calibredb-search--update-list ()
  "Update `calibredb-search-entries' list."
  ;; replace space with _ (SQL) The underscore represents a single character
  (let* ((filter calibredb-search-filter) ;; (replace-regexp-in-string " " "_" calibredb-search-filter)
         (head (calibredb-candidate-filter filter)))
    ;; Determine the final list order
    (let ((entries head))
      (setf calibredb-search-entries
            entries))))

(defun calibredb-search-print-entry--default (entry)
  "Print ENTRY to the buffer."
  (unless (equal entry "")
    (let ((content (car entry)) beg end)
      (setq beg (point))
      (insert content)
      (calibredb-detail-view-insert-image entry)
      (setq end (point))
      (put-text-property beg end 'calibredb-entry entry))))

(defun calibredb-search--minibuffer-setup ()
  "Set up the minibuffer for live filtering."
  (when calibredb-search-filter-active
    (when (eq :live calibredb-search-filter-active)
      (add-hook 'post-command-hook 'calibredb-search--live-update nil :local))))

(defun calibredb-search--live-update ()
  "Update the calibredb-search buffer based on the contents of the minibuffer."
  (when (eq :live calibredb-search-filter-active)
    ;; (message "HELLO")
    (let ((buffer (calibredb-search-buffer))
          (current-filter (minibuffer-contents-no-properties)))
      (when buffer
        (with-current-buffer buffer
          (let ((calibredb-search-filter current-filter))
            (calibredb-search-update :force)))))))

(defun calibredb-search-live-filter ()
  "Filter the calibredb-search buffer as the filter is written."
  (interactive)
  (unwind-protect
      (let ((calibredb-search-filter-active :live))
        (setq calibredb-search-filter
              (read-from-minibuffer "Filter: " calibredb-search-filter))
        (message calibredb-search-filter))
    (calibredb-search-update :force)))

(defun calibredb-search-keyword-filter (keyword)
  "Filter the calibredb-search buffer with KEYWORD."
  (setq calibredb-search-filter keyword)
  (calibredb-search-update :force))

(defun calibredb-search-update (&optional force)
  "Update the calibredb-search buffer listing to match the database.
When FORCE is non-nil, redraw even when the database hasn't changed."
  (interactive)
  (with-current-buffer (calibredb-search-buffer)
    (when force
      (let ((inhibit-read-only t)
            (standard-output (current-buffer)))
        (erase-buffer)
        (calibredb-search--update-list)
        ;; (setq calibredb-search-entries (calibredb-candidates))
        (dolist (entry calibredb-search-entries)
          (funcall calibredb-search-print-entry-function entry)
          (insert "\n"))
        ;; (insert "End of entries.\n")
        (goto-char (point-min))         ; back to point-min after filtering
        (setf calibredb-search-last-update (float-time))))))

;;; detail view

(defun calibredb-toggle-view ()
  "Toggle between detail view or compact view in *calibredb-search* buffer."
  (interactive)
  (setq calibredb-detial-view (if (eq calibredb-detial-view nil) t nil))
  (calibredb-search-toggle-view-refresh))

(defun calibredb-detail-view-insert-image (entry)
  "Insert image in *calibredb-search* under detail view based on ENTRY."
  (if (and calibredb-detial-view calibredb-detial-view-image-show)
      (let* ((num (cond (calibredb-format-all-the-icons 3)
                        (calibredb-format-icons-in-terminal 3)
                        ((>= calibredb-id-width 0) calibredb-id-width)
                        (t 0 )))
             (file (calibredb-getattr (cdr entry) :file-path))
             (format (calibredb-getattr (cdr entry) :book-format))
             (cover (concat (file-name-directory file) "cover.jpg")))
          (if (image-type-available-p (intern format))
              (progn
                (insert "\n")
                (insert (make-string num ? ))
                (calibredb-insert-image file "" calibredb-detail-view-image-max-width calibredb-detail-view-image-max-height))
            (progn
              (insert "\n")
              (insert (make-string num ? ))
              (calibredb-insert-image cover "" calibredb-detail-view-image-max-width calibredb-detail-view-image-max-height))))))

(defun calibredb-toggle-view-at-point ()
  "Toggle between detail view or compact view in *calibredb-search* buffer at point."
  (interactive)
  (let ((inhibit-read-only t)
        (status calibredb-detial-view))
    (if calibredb-detial-view
        ;; detail view
        (cond
         ;; save to calibredb-entry
         ((get-text-property (point) 'calibredb-entry nil)
          (setq calibredb-detial-view nil)
          (let* ((original (get-text-property (point) 'calibredb-entry nil))
                 (entry (cadr original))
                 (format (list (calibredb-format-item entry)))
                 ;; (position (seq-position calibredb-search-entries original))
                 (id (calibredb-get-init "id" (cdr (get-text-property (point) 'calibredb-entry nil)))) ; the "id" of current point
                 d-beg d-end)
            (if (equal id (calibredb-get-init "id" (cdr (get-text-property (point-min) 'calibredb-entry nil))))
                (setq d-beg (point-min))
              (save-excursion (while (equal id (calibredb-get-init "id" (cdr (get-text-property (point) 'calibredb-entry nil))))
                                (forward-line -1))
                              (forward-line 1)
                              (setq d-beg (point))))
            (save-excursion (while (equal id (calibredb-get-init "id" (cdr (get-text-property (point) 'calibredb-entry nil))))
                              (forward-line 1))
                            (goto-char (1- (point)))
                            (setq d-end (point)))
            (delete-region d-beg d-end)
            (save-excursion
              (unless (equal format "")
                (let ((content (car format))
                      (list (cons (car format) (list entry)))
                      beg end)
                  (setq beg (point))
                  (insert content)
                  (setq end (point))
                  (put-text-property beg end 'calibredb-compact list)))))
          (setq calibredb-detial-view status))

         ;; save to calibredb-compact
         ((get-text-property (point) 'calibredb-compact nil)
          (setq calibredb-detial-view t)
          (let* ((original (get-text-property (point) 'calibredb-compact nil))
                 (entry (cadr original))
                 (format (list (calibredb-format-item entry))))
            (delete-region (line-beginning-position) (line-end-position))
            (save-excursion
              (unless (equal format "")
                (let ((content (car format))
                      (list (cons (car format) (list entry)))
                      beg end)
                  (setq beg (point))
                  (insert content)
                  (calibredb-detail-view-insert-image original)
                  (setq end (point))
                  (put-text-property beg end 'calibredb-entry list)))))
          (setq calibredb-detial-view status)))

      ;; compact view
      (cond
       ;; save to calibredb-entry
       ((get-text-property (point) 'calibredb-entry nil)
        (setq calibredb-detial-view t)
        (let* ((original (get-text-property (point) 'calibredb-entry nil))
               (entry (cadr original))
               (format (list (calibredb-format-item entry))))
          (delete-region (line-beginning-position) (line-end-position))
          (save-excursion
            (unless (equal format "")
              (let ((content (car format))
                    (list (cons (car format) (list entry)))
                    beg end)
                (setq beg (point))
                (insert content)
                (calibredb-detail-view-insert-image original)
                (setq end (point))
                (put-text-property beg end 'calibredb-detail list)))))
        (setq calibredb-detial-view status))

       ;; save to calibredb-detail
       ((get-text-property (point) 'calibredb-detail nil)
        (setq calibredb-detial-view nil)
        (let* ((original (get-text-property (point) 'calibredb-detail nil))
               (entry (cadr original))
               (format (list (calibredb-format-item entry)))
               (id (calibredb-get-init "id" (cdr (get-text-property (point) 'calibredb-detail nil)))) ; the "id" of current point
               d-beg d-end)
          (if (equal id (calibredb-get-init "id" (cdr (get-text-property (point-min) 'calibredb-detail nil))))
              (setq d-beg (point-min))
            (save-excursion (while (equal id (calibredb-get-init "id" (cdr (get-text-property (point) 'calibredb-detail nil))))
                              (forward-line -1))
                            (forward-line 1)
                            (setq d-beg (point))))
          (save-excursion (while (equal id (calibredb-get-init "id" (cdr (get-text-property (point) 'calibredb-detail nil))))
                            (forward-line 1))
                          (goto-char (1- (point)))
                          (setq d-end (point)))
          (delete-region d-beg d-end)
          (save-excursion
            (unless (equal format "")
              (let ((content (car format))
                    (list (cons (car format) (list entry)))
                    beg end)
                (setq beg (point))
                (insert content)
                (setq end (point))
                (put-text-property beg end 'calibredb-entry list)))))
        (setq calibredb-detial-view status))))))


(provide 'calibredb-search)

;;; calibredb-search.el ends here
