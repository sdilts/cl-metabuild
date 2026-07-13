(in-package #:metabuild)

(defun %print-file-header (proj file-source stream)
  (declare (type project-config proj)
		   (type stream stream))
  (format stream ";; This file was generated for the system ~S."
		  (asdf:component-name (project-config-system proj)))
  (format stream "~%;; Edit the build file at ~A~%;; instead of changing this file."
		  file-source)
  (format stream "~%;;~%;; Creation Date: ~A" (local-time:format-timestring nil (local-time:now))))

(defun %insert-declarations (proj stream)
  (declare (type project-config proj)
		   (type stream stream))
  (when (project-config-optimization proj)
	(format stream  "~%")
	(pprint `(declaim ,(project-config-optimization proj))
			stream)))

(defun %generate-features-insert (proj stream)
  (declare (type project-config proj))
  (let ((forms (loop for f in (project-config-features proj)
					 append (when (feature-spec-enabled f)
							  (list `(cl:pushnew ,(feature-spec-feature f)
												 *features*))))))
	(format stream "~%~%;; Enabled features:")
	(pprint `(progn ,@forms) stream)))

(defun %build-source-registry-param (proj)
  `(:source-registry
		   ,@(reverse (project-config-source-registry proj))
				   :ignore-inherited-configuration))

(defun %generate-asdf-config (proj source-registry-param stream)
  (declare (type project-config proj))
  (let ((output-translations
		  `(quote (:output-translations
				   :inherit-configuration
				   (,(namestring (project-config-base-path proj))
					,(namestring (project-asdf-cache proj)))))))
	(format stream "~%~%;; Isolate where ASDF searches for systems")
	(pprint (list 'asdf:initialize-source-registry
				  (list 'quote source-registry-param))
			stream)
	(format stream "~%~%;; Place the compilation results from files")
	(format stream "~%;; in this project in the build directory")
	(pprint (list 'asdf:initialize-output-translations
				  output-translations)
			stream)))

(defun generate-init-env (proj source-registry)
  "Generate the init-build-env.lisp file that initializes the
features and ASDF environment"
  (declare (type project-config proj))
  (let ((path (make-pathname
			   :directory (pathname-directory (project-config-build-dir proj))
			   :name "init-build-env"
			   :type "lisp")))

	(with-open-file (stream path :direction :output :if-exists :supersede)
	  (%print-file-header proj (project-config-build-file proj) stream)
	  (pprint `(require "asdf") stream)
	  (%insert-declarations proj stream)
	  (%generate-features-insert proj stream)
	  (%generate-asdf-config proj source-registry stream)
	  (format stream "~&"))
	path))

(defun generate-build-exec-script (proj init-path)
  (declare (type project-config proj))
  (let ((path (make-pathname
			   :directory (pathname-directory (project-config-build-dir proj))
			   :name "build"
			   :type "lisp")))
	(with-open-file (stream path :direction :output :if-exists :supersede)
	  (with-accessors ((build-file project-config-build-file)
					   (exec-sys project-config-exec-system)
					   (sys project-config-system))
		  proj
		(%print-file-header proj (project-config-build-file proj) stream)
		(pprint `(load ,init-path)
				stream)
		(pprint (list 'asdf:make (asdf:component-name
								  (if exec-sys
									  exec-sys
									  sys)))
				stream)
		(format stream "~&")))
	path))

(defun %internal-dir (proj)
  (declare (type project-config proj))
  (append
   (pathname-directory (project-config-build-dir
						proj))
   (list "internal")))

(defun %write-state-file (proj build-state)
  (let* ((internal-dir (%internal-dir proj))
		(path (make-pathname
			   :directory internal-dir
			   :name "state"
			   :type "sexp")))
	(ensure-directories-exist (make-pathname :directory internal-dir))
	(with-open-file (stream path :direction :output :if-exists :supersede)
	  (pprint build-state stream))))

(defun %write-ninja-file (proj init-file build-script)
  (declare (optimize (debug 3)))
  (flet ((relativize-path (p)
		   (enough-namestring p (project-config-build-dir proj))))
	(setf init-file (relativize-path init-file)
		  build-script (relativize-path build-script))
  (let ((path (merge-pathnames "build.ninja" (project-config-build-dir proj))))
	(with-open-file (os path :direction :output :if-exists :supersede)
	  (let ((s (ninja:make-line-wrapping-stream os))
			(compiler (project-config-compiler proj)))
		(ninja:write-bindings s "lisp_impl"
							  (compiler-load-cmd
							   compiler
							  "$in"
							  :impl-flags (gethash (compiler-name compiler)
												   (project-config-compiler-flags proj))))
		(format s "~%")
		(ninja:write-rule s "REGENERATE_BUILD"
						  :command
						  (compiler-load-cmd
						   compiler
						   (relativize-path (project-config-build-file proj))
						   :exec-flags (list "--state" "internal/state.sexp"))
						  :description "Regenerating build files"
						  :generator 1)
		(ninja:write-rule s "LISP"
						  :command "$lisp_impl $in"
						  :pool "console")
		(let ((outputs (list (project-exec-output proj))))
		  (ninja:write-build s "LISP"
							 :outputs (mapcar #'relativize-path outputs)
							 :inputs (list build-script)))
		(let ((outputs (list path init-file build-script))
			  (inputs (list (project-config-build-file proj)
							(asdf:system-source-file
							 (project-config-system proj)))))
		  ;; Putting the ASDF files here ensures that new dependencies are
		  ;; picked up:
		  (when (project-config-exec-system proj)
			(push (project-config-exec-system proj) inputs))
		  (ninja:write-build s "REGENERATE_BUILD"
							 :outputs (mapcar #'relativize-path outputs)
							 :inputs (mapcar #'relativize-path inputs)))
		(ninja:write-default s (relativize-path (project-exec-output proj))))))))


(defun emit-all-files (project)
  (declare (type project-config project))
  (let* ((source-registry-param (%build-source-registry-param project))
		 (vendored (download-dependencies project source-registry-param)))
	(print-summary project)
	(format *error-output* "~%Generating output files...")
	(finish-output *error-output*)
	(ensure-directories-exist (project-config-build-dir project))
	(let* ((init-file-path (generate-init-env project source-registry-param))
		   (build-script (generate-build-exec-script project init-file-path)))
	  (let ((build-state (extract-build-state project vendored)))
		(%write-state-file project build-state))
	  (%write-ninja-file project init-file-path build-script))
	(format *error-output* "~%Done! You can now build the project.~%")))

(defun finish-configure (project)
  (let ((last-state nil))
	(let ((parser (build-cmd-line-parser project)))
	  (multiple-value-bind (pos opts)
		  (adopt:parse-options parser)
		(declare (ignore pos))
		(setf last-state (apply-command-line-opts parser opts project))))
	(when (and last-state
			   (needs-whole-rebuild project last-state)
			   (uiop:directory-exists-p (project-asdf-cache project)))
	  ;; Something changed so that we can't use the old compilation
	  ;; results. Remove them before continuing:
	  (format *error-output* "~&Build settings changed, removing old compilation results...")
	  (uiop:delete-directory-tree (project-asdf-cache project) :validate t)
	  (format *error-output* "~%Done!"))
	(emit-all-files project))
  (uiop:quit 0))
