(in-package #:static-build)

(defmacro with-env-values (value-spec &body body)
  (let ((vars (mapcar (lambda (x)
						(cons (gensym (car x)) x))
					  value-spec))
		(val-or-blank (gensym "val-or-blank")))
	`(let (,@(mapcar (lambda (x)
					   (list (car x) `(uiop:getenv ,(second x))))
					 vars))
	   (setf ,@(loop for v in vars
					 append (list `(uiop:getenv ,(second v)) (third v))))
	   ,@body
	   (flet ((,val-or-blank (val)
				(if val val "")))
		 (setf ,@(loop for v in vars
					   append (list `(uiop:getenv ,(second v)) `(,val-or-blank ,(car v)))))))))

(defun program-availabe-p (program-name)
  (let (
		#+unix
		(find-command (list "which" program-name))
		#+windows
		(find-command (list "where" "ocicl")))
	(multiple-value-bind (output err-output code)
		(uiop:run-program find-command :ignore-error-status t)
	  (declare (ignore output err-output))
	  (zerop code))))

(defun pathname-under-p (under top)
  (if (and under top)
	  (not (eq :absolute (car (pathname-directory
							   (enough-namestring (truename under)
												  (truename top))))))
	  nil))
