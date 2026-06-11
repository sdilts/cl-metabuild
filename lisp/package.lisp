(defpackage #:static-build
  (:use :cl)
  (:export
   #:with-project
   #:finish-configure
   #:add-features
   #:add-system-directories
   #:add-system-trees
   #:print-summary))
