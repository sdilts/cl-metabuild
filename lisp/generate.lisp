(in-package #:static-build)

(defun %print-file-header (proj file-source stream)
  (declare (type project-config proj)
		   (type stream stream))
  (format stream ";; This file was generated for the system ~S."
		  (asdf:component-name (project-config-system proj)))
  (format stream "~%;; Edit the build file at ~A~%;; instead of changing this file."
		  file-source)
  (format stream "~%;;~%;; Creation Date: ~A" (local-time:format-timestring nil (local-time:now))))

(defun %insert-declarations (proj stream)
  (when (project-config-optimization proj)
	(format stream  "~%")
	(pprint `(declaim ,(project-config-optimization proj))
			stream)))

(defun %generate-features-insert (proj stream)
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
		(format stream "~&")))))

(defmacro with-missing-dependency-fetcher ((project source-registry-param)
										   &body body)
  (let ((handle-missing-dependency (gensym "handle-missing-dependency"))
		(registry-param (gensym "registry-param")))
	`(let ((,registry-param ,source-registry-param))
	   (flet ((,handle-missing-dependency (c)
				(let ((missing-req (asdf/find-component:missing-requires c)))
				  (format *error-output* "~&Missing dependency: ~S~%"
						  missing-req)
				  (finish-output *error-output*)
				  (install-dependencies
				   (project-config-package-source ,project)
				   ,project
				   (list missing-req))
				  ;; ASDF won't find the new package unless the source
				  ;; registry is reset:
				  (asdf:initialize-source-registry ,registry-param)
				  (invoke-restart 'asdf:retry))))
		 ;; We could just add something to
		 ;; asdf:*system-definition-search-functions*
		 ;; instead of this, but I'm less
		 ;; confident of the results. Maybe it would be faster?
		 (handler-bind ((asdf:missing-dependency
						  (function ,handle-missing-dependency)))
		   ,@body)))))

(defun %find-sys (project source-registry-param system-name)
  (with-missing-dependency-fetcher (project source-registry-param)
	(asdf:find-system system-name nil)))

(defun %find-missing-dependencies (project dependencies source-registry-param)
  (let ((pkg-src (project-config-package-source project))
		(missing nil)
		(vendored nil))
	(declare (optimize (debug 3)))
	(dolist (d dependencies)
	  (let ((sys (%find-sys project source-registry-param d)))
		(if sys
			(unless (system-from-source-p
					 pkg-src sys)
			  (push sys vendored))
			(push d missing))))
	(values missing vendored)))

(defun download-dependencies (project source-registry-param)
  (declare (type project-config project))
  ;; We need to clear this project's dependencies so they
  ;; aren't counted as present:
  (let ((cur-sys (asdf:find-system "static-build")))
	(dolist (d (asdf:system-depends-on cur-sys))
	  (asdf:clear-system d)))
  (format *error-output* "~%Checking project dependencies...~%")
  (asdf:initialize-source-registry source-registry-param)
  (let* ((dependencies (asdf:system-depends-on (project-config-system project))))
	(multiple-value-bind (missing vendored)
		(%find-missing-dependencies project dependencies source-registry-param)
	  (when vendored
		(format *error-output* "Checking dependencies of vendored systems:~{ ~A~}~%"
				vendored)
		(dolist (v vendored)
		  (let ((v-deps (asdf:system-depends-on v)))
			(dolist (d v-deps)
			  (unless (%find-sys project source-registry-param d)
				(push d missing))))))
	  (when missing
		(format *error-output* "Missing systems:~{ ~A~}~%"
				missing)
		(install-dependencies (project-config-package-source project)
							  project missing)))))

(defun finish-configure (project)
  (let ((parser (build-cmd-line-parser project)))
	(multiple-value-bind (pos opts)
		(adopt:parse-options parser)
	  (declare (ignore pos))
	  (apply-command-line-opts parser opts project)))
  (let ((source-registry-param (%build-source-registry-param project)))
	(download-dependencies project source-registry-param)
	(print-summary project)
	(format *error-output* "~%Generating output files...")
	(finish-output *error-output*)
	(ensure-directories-exist (project-config-build-dir project))
	(let ((init-file-path (generate-init-env project source-registry-param)))
	  (generate-build-exec-script project init-file-path))
	(format *error-output* "~%Done! You can now build the project.~%")))
