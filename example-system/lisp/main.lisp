(defpackage #:metabuild/example-system
  (:use :cl))

(in-package #:metabuild/example-system)

#+PRINT-NAME
(defun main ()
  (let ((args (uiop:command-line-arguments)))
	(alexandria:if-let ((name (first args)))
	  (format t "Hello, ~A~%" name)
	  (format t "Hello, World!~%"))))

#-PRINT-NAME
(defun main ()
  (format t "Hello, World!~%"))
