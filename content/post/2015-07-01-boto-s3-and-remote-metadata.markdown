---
date: "2015-07-01T00:00:00Z"
summary: Setting remote metadata for files on s3 might be tricky, lets take a peek
title: Boto, s3 and remote metadata
---

Using boto to store files on s3 might be a little bit confusing when it comes to store metadata for files. Normally you would expect that ``key.set_metadata`` saves data remotely on s3. In fact ``set_metadata`` stores your keys locally in python dict.

{{< highlight python >}}
>>> bucket.new_key('testing-file')
>>> key.set_contents_from_string('testing content')
>>> key.set_metadata('hello', 'from metadata')
>>> key.get_metadata('hello')
>>> 'from metadata'
{{< / highlight >}}

In example above you can get metadata form key instance, but what if you get your file from s3 again? Metadata will be a empty dict.

{{< highlight python >}}
>>> key.get_metadata('hello') is None
>>> True
{{< / highlight >}}

``set_remote_metadata`` is the method you probably are looking for.

{{< highlight python >}}
>>> key.set_remote_metadata?
Type:       instancemethod
String Form:<bound ey:="" ="" key.set_remote_metadata="" method="" of="" testing-file="">&gt;
File:       /lib/python2.7/site-packages/boto/s3/key.py
Definition: key.set_remote_metadata(self, metadata_plus, metadata_minus, preserve_acl, headers=None)
Docstring:  no docstring=""
{{< / highlight >}}

Interface to that method is more then weird but it does the job.

{{< highlight python >}}
>>> key = bucket.get_key('testing-file')
>>> key.set_remote_metadata({'hello': 'this is remote metadata'}, {}, True)
>>> remote_key = bucket.get_key('testing-file')
>>> remote_key.metadata
>>> {'hello': u'this is remote metadata'}
{{< / highlight >}}

In fact boto stores files metadata in headers by adding <b>x-amx-meta</b> prefix, you can check that by downloading file directly.
{{< highlight python >}}
>>> requests.get('https://you_bucket.s3.amazonaws.com/testing-file').headers['x-amz-meta-hello']
>>> this is remote metadata'
{{< / highlight >}}

If you want to update file headers without meta prefix, you can do it easily:
{{< highlight python >}}
>>> key.set_remote_metadata({'Content-Type': 'custom/type'}, {}, True)
>>> requests.get('https://{}.s3.amazonaws.com/testing-file').headers['content-type']
>>> 'custom/type'
{{< / highlight >}}
