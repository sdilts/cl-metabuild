(in-package #:static-build)

(defstruct build-state
  (system nil :type string :read-only t)
  (exec-sys nil :type (or null string) :read-only t)
  (test-sys nil :type (or null string) :read-only t)
  ;; The file that defines the build:
  (build-file nil :type pathname :read-only t)
  ;; The root of the project directory:
  (base-path nil :type pathname :read-only t)
  ;; the name of the package source:
  (pkg-source nil :type package-source :read-only t)
  ;; Where the build artifacts get placed:
  (build-dir nil :type pathname)
  ;; A list of paths to vendored systems:
  (vendored nil :type list :read-only t)
  ;; The source registry configuration:
  (source-registry nil :type list :read-only t)
  ;; The optimization declaration:
  (optimization nil :type list :read-only t)
  ;; Symbols pushed to *features*:
  (features nil :type list))

(defun extract-build-state (config vendored)
  (declare (type project-config config)
		   (optimize (debug 3)))
  (with-accessors ((exec-system project-config-exec-system)
				   (test-system project-config-test-system)
				   (optimization project-config-optimization)
				   (base-path project-config-base-path)
				   (features project-config-features))
	  config
	(make-build-state
	 :system (asdf:component-name (project-config-system config))
	 :exec-sys (when exec-system (asdf:component-name exec-system))
	 :test-sys (when test-system (asdf:component-name test-system))
	 :build-file (project-config-build-file config)
	 :base-path base-path
	 :pkg-source (project-config-package-source config)
	 :build-dir (project-config-build-dir config)
	 :source-registry (project-config-source-registry config)
	 :vendored (remove-if #'null (mapcar #'asdf:system-source-file vendored))
	 :optimization optimization
	 :features features)))

(defun keyed-difference (a b &key (id #'identity) (test #'eq))
  (let ((a-table (make-hash-table)))
	(dolist (f a)
	  (setf (gethash (funcall id f) a-table) f))
	(dolist (f b)
	  (let* ((other (gethash (funcall id f) a-table))
			 (changed (not (if other
							   (funcall test f other)
							   nil))))
		(when changed
		  (return-from keyed-difference t)))))
  nil)

(defun compare-features (a b)
  "Return T if any of the features are different between the two
lists"
  (flet ((enabled-eq (f1 f2)
		   (declare (type feature-spec f1 f2))
		   (eq (feature-spec-enabled f1) (feature-spec-enabled f2))))
	(keyed-difference a b :id #'feature-spec-feature :test #'enabled-eq)))

(defun compare-optmization (a b)
  (keyed-difference a b :id #'car :test (lambda (x y)
										  (= (second x) (second y)))))

(defun needs-whole-rebuild (project last-state)
  "Return a T if a whole rebuild is needed."
  (declare (type project-config project)
		   (type build-state last-state))
  (or (compare-features (project-config-features project)
						(build-state-features last-state))
	  (compare-optmization (cdr (project-config-optimization project))
						   (cdr (build-state-optimization last-state)))
	  (not (equal (project-config-source-registry project)
						(build-state-source-registry last-state)))
	  (not (package-source-equals (project-config-package-source project)
										(build-state-pkg-source last-state)))))


(defun read-build-state (state-file-path)
  (declare (type string state-file-path))
  (let* ((path (uiop:parse-native-namestring state-file-path))
		 (full-path (merge-pathnames path (uiop:getcwd))))
	(uiop:with-safe-io-syntax ()
	  (uiop:read-file-form full-path))))
