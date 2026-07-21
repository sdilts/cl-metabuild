#!/usr/bin/env -S sbcl --script

;; This is an annotated version of an example setup.lisp file. Parts
;; of it are different so that it works within this project without a bundle file,
;; but the gist is the same.

;; If you want users to be able to use quicklisp,
;; include this form, which will load it:
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp"
									   (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

;; We need ASDF; Load this after quicklisp so quicklisp can include their own
;; version
(require 'asdf)

;; We need to load the cl-metabuild system and make the project itself
;; visible to ASDF. The section between here
;; and the `with-project` form does that. For normal usage,
;; you can just load the cl-metabuild bundle with:
;;  (load "path/to-cl-metabuild/")
;; You still need to make the project visible to ASDF though.
(defun cur-dir ()
  (make-pathname
   :directory (pathname-directory (or *load-truename* *compile-file-pathname*))))

(defun metabuild-system-dir ()
  "Get the parent directory of this file. Will only work if this
file is loaded or compiled, and not when interactively evaluated."
  (let* ((cur-dir (cur-dir))
		 (path-type (car (pathname-directory cur-dir)))
		 (dir-list (cons path-type (reverse
									(cdr (reverse
										  (cdr (pathname-directory cur-dir))))))))
	(make-pathname :directory dir-list)))

(let ((src-registry (list :source-registry
						  ;; Make the cl-metabuild system visible to the environment:
						  (list :directory (metabuild-system-dir))
						  ;; Make the example project visible to ASDF:
						  (list :directory (cur-dir))
						  :inherit-configuration)))
  (finish-output)
  (asdf:initialize-source-registry
   src-registry))

(asdf:load-system "cl-metabuild")

(metabuild:with-project project
	;; the name of your system. If there's a separate system
	;; that defines the executable, specify it here:
	("example-system" :exec-system "example-system/executable")
  ;; Set what gets pushed to *FEATURES*:
  (metabuild:add-features project
						  (:print-name :default t))
  ;; Set the optimization levels for the project.
  (metabuild::set-optimization project
							   :debug 0 :speed 3 :safety 0)
  ;; Generate the files:
  (metabuild:finish-configure project))
