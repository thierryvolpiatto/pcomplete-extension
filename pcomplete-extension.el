;;; pcomplete-extension.el --- additional completion for pcomplete -*- lexical-binding: t -*-

;; Copyright (C) 2010 ~ 2013 Thierry Volpiatto <thierry.volpiatto@gmail.com>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.


;;; Code:

(require 'cl-lib)
(require 'pcomplete)
(require 'shell)


;;; Hg completion
;;
;;
(cl-defun pcomplete-get-hg-commands (&key com opts spec)
  (with-temp-buffer
    (let (h1 h2 h3)
      (if spec
          (progn
            (apply #'call-process "hg" nil t nil
                   (list "-v" "help" spec))
            (setq h3 (buffer-string)))
          (call-process "hg" nil t nil
                        "-v" "help")
          (setq h1 (buffer-string))
          (erase-buffer)
          (apply #'call-process "hg" nil t nil
                 (list "-v" "help" "mq"))
          (setq h2 (buffer-string)))
      (erase-buffer)
      (if spec (insert h3) (insert (concat h1 h2)))
      (goto-char (point-min))
      (let (args coms sargs)
        (if spec
            (setq sargs (cl-loop while (re-search-forward "\\(-[a-zA-Z]\\|--[a-zA-Z]+\\) *" nil t)
                                 collect (match-string 1)))
            (save-excursion
              (setq coms
                    (cl-loop while (re-search-forward "^ \\([a-z]+\\) *" nil t)
                             collect (match-string 1))))
            (setq args
                  (cl-loop while (re-search-forward "\\(-[a-zA-Z]\\|--[a-zA-Z]+\\) *" nil t)
                           collect (match-string 1))))
        (cond (spec sargs)
              (com coms)
              (opts args)
              (t (list args coms)))))))

(defvar pcomplete-hg-commands-cache nil)
(defvar pcomplete-hg-glob-opts-cache nil)
(defun pcomplete/hg ()
  (let* ((cur      (pcomplete-arg 'first))
         (avder    (pcomplete-arg 0))
         (last     (pcomplete-arg 'last))
         (all      (pcomplete-get-hg-commands))
         (commands (or pcomplete-hg-commands-cache
                       (setq pcomplete-hg-commands-cache
                             (cadr all))))
         (options  (or pcomplete-hg-glob-opts-cache
                       (setq pcomplete-hg-glob-opts-cache
                             (car all))))
         (special  (pcomplete-get-hg-commands :spec avder)))
    (cond ((and (string-match-p "^-" last)
                (member avder commands))
           (while (pcomplete-here special)))
          ((string-match-p "^-" last)
           (pcomplete-here options))
          ((string-match-p "qqueue" avder)
           (let ((queues (with-temp-buffer
                           (apply #'call-process "hg" nil t nil
                                  (list "qqueue" "-l"))
                           (cl-loop for i in (split-string (buffer-string) "\n" t)
                                    append (list (car (split-string i " (")))))))
             (while (pcomplete-here queues))))
          ((and (string= cur "hg")
                (not (string= cur avder)))
           (pcomplete-here commands)))
    (while (pcomplete-here (pcomplete-entries) nil 'identity))))


;;; Find completion
;;
;;
(defun pcomplete/find ()
  (let ((prec (pcomplete-arg 'last -1)))
    (cond ((and (pcomplete-match "^-" 'last)
                (string= "find" prec))
           ;; probably in sudo, work-around: increase index
           ;; otherwise pcomplete-opt returns nil
           (when (< pcomplete-index pcomplete-last)
             (pcomplete-next-arg))
           (pcomplete-opt "HLPDO"))
          ((pcomplete-match "^-" 'last)
           (while (pcomplete-here
                   '("-amin" "-anewer" "-atime" "-cmin" "-cnewer" "-context"
                     "-ctime" "-daystart" "-delete" "-depth" "-empty" "-exec"
                     "-execdir" "-executable" "-false" "-fls" "-follow" "-fprint"
                     "-fprint0" "-fprintf" "-fstype" "-gid" "-group"
                     "-help" "-ignore_readdir_race" "-ilname" "-iname"
                     "-inum" "-ipath" "-iregex" "-iwholename"
                     "-links" "-lname" "-ls" "-maxdepth"
                     "-mindepth" "-mmin" "-mount" "-mtime"
                     "-name" "-newer" "-nogroup" "-noignore_readdir_race"
                     "-noleaf" "-nouser" "-nowarn" "-ok"
                     "-okdir" "-path" "-perm" "-print"
                     "-print0" "-printf" "-prune" "-quit"
                     "-readable" "-regex" "-regextype" "-samefile"
                     "-size" "-true" "-type" "-uid"
                     "-used" "-user" "-version" "-warn"
                     "-wholename" "-writable" "-xdev" "-xtype"))))
          ((string= "-type" prec)
           (while (pcomplete-here (list "b" "c" "d" "p" "f" "l" "s" "D"))))
          ((string= "-xtype" prec)
           (while (pcomplete-here (list "b" "c" "d" "p" "f" "l" "s"))))
          ((or (string= prec "-exec")
               (string= prec "-execdir"))
           (while (pcomplete-here* (funcall pcomplete-command-completion-function)
                                   (pcomplete-arg 'last) t))))
    (while (pcomplete-here (pcomplete-dirs) nil 'identity))))


;;; Sudo
;;
;; Allow completing other commands entered after sudo
;; FIXME short options are not working after sudo.
(defun pcomplete/sudo ()
  (let ((pcomplete-cmd-name (pcomplete-command-name)))
    (while (and (string= "sudo" pcomplete-cmd-name)
                (pcomplete-match "^-" 'last))
      (when (< pcomplete-index pcomplete-last)
        (pcomplete-next-arg))
      (pcomplete-opt "AbCDEegHhiKknPpSsUuVv-"))
    (cond ((string= "sudo" pcomplete-cmd-name)
           (while (pcomplete-here*
                   (funcall pcomplete-command-completion-function)
                   (pcomplete-arg 'last) t)))
          (t
           (funcall (or (pcomplete-find-completion-function
                         pcomplete-cmd-name)
                        pcomplete-default-completion-function))))))


;;; Redefine emacs core functions to have completion after sudo
;;
(defun shell-command-completion-function ()
  "Completion function for shell command names.
This is the value of `pcomplete-command-completion-function' for
Shell buffers.  It implements `shell-completion-execonly' for
`pcomplete' completion."
  (let* ((data (shell--command-completion-data))
         (input (and data (buffer-substring (nth 0 data) (nth 1 data)))))
    (if (and data (not (string-match-p "\\`[.]\\{1\\}/" input)))
        (pcomplete-here (all-completions "" (nth 2 data)))
        (pcomplete-here (pcomplete-entries nil
                                           (if shell-completion-execonly
                                               'file-executable-p))))))

(defvar pcomplete-special-commands '("sudo" "xargs"))
(defun pcomplete-command-name ()
  "Return the command name of the first argument."
  (let ((coms (cl-loop with lst = (reverse (pcomplete-parse-arguments))
                       for str in (or (member "|" lst)
                                      (member "||" lst)
                                      (member "&" lst)
                                      (member ";" lst)
                                      lst)
                       for exec = (or (executable-find str)
                                      ;; `executable-find' or 'which'
                                      ;; doesn't return these paths.
                                      (car (member str '("cd" "pushd" "popd"))))
                       when exec collect exec)))
    (file-name-nondirectory
     ;; we may have commands embeded in executables that looks
     ;; like executables (e.g apt-get install).
     ;; Assume that all executables are using only one command
     ;; like this.
     ;; e.g - if we have (install apt-get sudo)
     ;;       what we want is apt-get.
     ;;     - if we have (apt-get sudo)
     ;;       what we want is sudo,
     ;;       then pcomplete/sudo will check if
     ;;       a pcomplete handler exists for apt-get.
     (cond (;; e.g (install apt-get sudo)
            (> (length coms) 2) (cadr coms))
           (;; e.g (apt-get sudo)
            (and (= (length coms) 2)
                 (member (file-name-nondirectory (cadr coms))
                         pcomplete-special-commands))
            (car coms))
           (;; e.g (sudo)
            (= (length coms) 1) (car coms))
           (t ;; e.g (install apt-get)
            (cadr coms))))))

;;; Redefine pcomplete/* functions not working in emacs.
;;
(defun pcomplete/xargs ()
  "Completion for `xargs'."
  (let ((pcomplete-cmd-name (pcomplete-command-name)))
    (cond ((string= "xargs" pcomplete-cmd-name)
           (while (pcomplete-here*
                   (funcall pcomplete-command-completion-function)
                   (pcomplete-arg 'last) t)))
          (t (funcall (or (pcomplete-find-completion-function
                           pcomplete-cmd-name)
                          pcomplete-default-completion-function))))))

;; Avoid infloop in cd. e.g "sudo cd /" <TAB>
;; Even if it is not allowed to do this.
(defun pcomplete/cd ()
  "Completion for `cd'."
  (while (pcomplete-here (pcomplete-dirs) nil 'identity)))

;; Tests
;; find . -name '*.el' | xargs et      =>ok
;; find . -name '*.el' | xargs -t et   =>ok
;; sudo apt-g                          =>ok
;; sudo apt-get in                     =>ok
;; sudo apt-get --                     =>ok
;; sudo apt-get -                      =>ok
;; sudo apt-get -V -                   =>ok
;; sudo apt-get -V --                  =>ok
;; sudo apt-get --reinstall ins        =>ok
;; sudo apt-get --reinstall install em =>ok
;; sudo -                              =>ok
;; sudo -p "pass" -                    =>ok
;; sudo -p "pass" apt-g                =>ok
;; sudo -p "pass" apt-get ins          =>ok
;; apt-get in                          =>ok
;; apt-get install em                  =>ok


;;; Ls
;;
(defun pcomplete/ls ()
  (while (pcomplete-match "^-" 'last)
    (cond ((pcomplete-match "^-\\{2\\}" 'last)
           (while (pcomplete-here
                   '("--all" "--almost-all" "--author"
                     "--escape" "--block-size=" "--ignore-backups" "--color="
                     "--directory" "--dired" "--classify" "--file-type"
                     "--format=" "--full-time" "--group-directories-first"
                     "--no-group" "--human-readable" "--si"
                     "--dereference-command-line-symlink-to-dir"
                     "--hide=" "--indicator-style=" "--inode" "--ignore="
                     "--dereference" "--numeric-uid-gid" "--literal" "--indicator-style="
                     "--hide-control-chars" "--show-control-chars"
                     "--quote-name" "--quoting-style=" "--reverse" "--recursive"
                     "--size" "--sort=" "--time=" "--time-style=--tabsize="
                     "--width=" "--context" "--version" "--help"))))
          ((pcomplete-match "^-\\{1\\}" 'last)
           ;; probably in sudo, work-around: increase index
           ;; otherwise pcomplete-opt returns nil
           (when (< pcomplete-index pcomplete-last)
             (pcomplete-next-arg))
           (pcomplete-opt "aAbBcCdDfFgGhHiIklLmnNopqQrRsStTuUvwxXZ1"))))
  (while (pcomplete-here (pcomplete-entries) nil 'identity)))


;;; apt-get
;;
(defvar pcomplete-apt-get-data nil)
(defun pcomplete/apt-get ()
  (let ((prec (pcomplete-arg 'last -1))
        (cmd-list '("autoclean" "changelog" "dist-upgrade" "install" "source" "autoremove"
                    "check" "download" "purge" "update" "build-dep" "clean" "dselect-upgrade"
                    "remove" "upgrade")))
    (while (pcomplete-match "^-" 'last)
      (cond ( ;; long options
             (pcomplete-match "\\`-\\{2\\}" 'last)
             (while (pcomplete-here
                     '("--no-install-recommends" "--install-suggests" "--download-only"
                       "--fix-broken" "--ignore-missing" "--fix-missing" "--no-download"
                       "--quiet" "--simulate" "--just-print" "--dry-run" "--recon" "--no-act"
                       "--yes" "--assume-yes" "--assume-no" "--show-upgraded" "--verbose-versions"
                       "--host-architecture" "--compile" "--build" "--ignore-hold"
                       "--no-upgrade" "--only-upgrade" "--force-yes" "--print-uris"
                       "--purge" "--reinstall" "--list-cleanup" "--target-release" "--default-release"
                       "--trivial-only" "--no-remove" "--auto-remove" "--only-source"
                       "--diff-only" "--dsc-only" "--tar-only" "--arch-only"
                       "--allow-unauthenticated" "--help" "--version" "--config-file" "--option"))))
            
            (;; short options
             (pcomplete-match "\\`-\\{1\\}" 'last)
             ;; probably in sudo, work-around: increase index
             ;; otherwise pcomplete-opt returns nil
             (when (< pcomplete-index pcomplete-last)
               (pcomplete-next-arg))
             (pcomplete-opt "dfmqsyuVabthvco"))))
    (cond (;; commands
           (or (string= prec "apt-get")
               (string-match "\\`--?" prec))
           (while (pcomplete-here* cmd-list (pcomplete-arg 'last))))
          ;; packages
          ((member prec cmd-list)
           (while (pcomplete-here
                   (if pcomplete-apt-get-data
                       pcomplete-apt-get-data
                       (message "[Wait loading apt db...]")
                       (setq pcomplete-apt-get-data
                             (with-temp-buffer
                               (call-process-shell-command
                                (format "apt-cache search '%s'" "")
                                nil (current-buffer))
                               (mapcar (lambda (line) (car (split-string line " - ")))
                                       (split-string (buffer-string) "\n")))))))))))


(provide 'pcomplete-extension)

;;; pcomplete-extension.el ends here
