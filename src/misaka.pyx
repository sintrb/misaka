cimport sundown
cimport wrapper

from sundown cimport buf

from libc.string cimport strdup
from libc.stdint cimport uint8_t
from cpython.string cimport PyString_FromStringAndSize, PyString_AsString, \
    PyString_Size


__version__ = '1.0.0'

# Markdown extensions
EXT_NO_INTRA_EMPHASIS = (1 << 0)
EXT_TABLES = (1 << 1)
EXT_FENCED_CODE = (1 << 2)
EXT_AUTOLINK = (1 << 3)
EXT_STRIKETHROUGH = (1 << 4)
EXT_LAX_HTML_BLOCKS = (1 << 5)
EXT_SPACE_HEADERS = (1 << 6)
EXT_SUPERSCRIPT = (1 << 7)

# HTML Render flags
HTML_SKIP_HTML = (1 << 0)
HTML_SKIP_STYLE = (1 << 1)
HTML_SKIP_IMAGES = (1 << 2)
HTML_SKIP_LINKS = (1 << 3)
HTML_EXPAND_TABS = (1 << 4)
HTML_SAFELINK = (1 << 5)
HTML_TOC = (1 << 6)
HTML_HARD_WRAP = (1 << 7)
HTML_USE_XHTML = (1 << 8)

# Deprecated: planned for removal in 1.1.0
# Extra HTML render flags - these are not from Sundown
HTML_SMARTYPANTS = (1 << 9)  # An extra flag to enabled Smartypants
HTML_TOC_TREE = (1 << 10)  # Only render a table of contents tree


# Deprecated: planned for removal in 1.1.0
def html(char *text, unsigned int extensions=0, unsigned int render_flags=0):

    cdef object result
    cdef sundown.buf *sb # Smartypants buffer

    cdef sundown.sd_callbacks callbacks
    cdef sundown.html_renderopt options
    cdef sundown.sd_markdown *markdown

    cdef sundown.buf *ib = sundown.bufnew(128)
    sundown.bufputs(ib, text)

    cdef sundown.buf *ob = sundown.bufnew(128)
    sundown.bufgrow(ob, <size_t> (ib.size * 1.4))

    if render_flags & HTML_TOC_TREE:
        sundown.sdhtml_toc_renderer(&callbacks, &options)
    else:
        sundown.sdhtml_renderer(&callbacks, &options, render_flags)

    markdown = sundown.sd_markdown_new(extensions, 16, &callbacks, &options)
    sundown.sd_markdown_render(ob, ib.data, ib.size, markdown)
    sundown.sd_markdown_free(markdown)

    if render_flags & HTML_SMARTYPANTS:
        sb = sundown.bufnew(128)
        sundown.sdhtml_smartypants(sb, ob.data, ob.size)
        sundown.bufrelease(ob)
        ob = sb

    result = PyString_FromStringAndSize(<char *> ob.data, ob.size)

    sundown.bufrelease(ob)
    sundown.bufrelease(ib)

    return result


cdef void *_overload(klass, sundown.sd_callbacks *callbacks):
    cdef void **source = <void **> &wrapper.callback_funcs
    cdef void **dest = <void **> callbacks

    for i from 0 <= i < <int> wrapper.method_count by 1:
        if hasattr(klass, wrapper.method_names[i]):
            dest[i] = source[i]


cdef class SmartyPants:
    def postprocess(self, object text):
        cdef sundown.buf *ob = sundown.bufnew(128)

        sundown.sdhtml_smartypants(ob,
            <uint8_t *> PyString_AsString(text), PyString_Size(text))
        cdef object result = PyString_FromStringAndSize(
            <char *> ob.data, ob.size)

        sundown.bufrelease(ob)
        return result


cdef class BaseRenderer:

    cdef sundown.sd_callbacks callbacks
    cdef wrapper.renderopt options

    def __init__(self, int render_flags=0):
        self.options.self = <void *> self
        _overload(self, &self.callbacks)


cdef class HtmlRenderer(BaseRenderer):

    def __init__(self, int render_flags=0):
        self.options.self = <void *> self
        self.options.html.flags = render_flags

        sundown.sdhtml_renderer(&self.callbacks,
            &self.options.html,
            self.options.html.flags)

        _overload(self, &self.callbacks)


cdef class HtmlTocRenderer(BaseRenderer):

    def __init__(self, int render_flags=0):
        self.options.self = <void *> self

        sundown.sdhtml_toc_renderer(&self.callbacks,
            &self.options.html)

        _overload(self, &self.callbacks)


cdef class Markdown:

    cdef sundown.sd_markdown *markdown
    cdef BaseRenderer renderer

    def __cinit__(self, object renderer, int extensions=0):
        if not isinstance(renderer, BaseRenderer):
            raise ValueError('expected instance of BaseRenderer, %s found' % \
                renderer.__class__.__name__)

        self.renderer = <BaseRenderer> renderer
        self.markdown = sundown.sd_markdown_new(
            extensions, 16,
            &self.renderer.callbacks,
            <sundown.html_renderopt *> &self.renderer.options)

    def render(self, char *text):
        cdef object result

        cdef sundown.buf *ib = sundown.bufnew(128)
        sundown.bufputs(ib, text)

        cdef sundown.buf *ob = sundown.bufnew(128)
        sundown.bufgrow(ob, <size_t> (ib.size * 1.4))

        sundown.sd_markdown_render(ob, ib.data, ib.size, self.markdown)

        result = PyString_FromStringAndSize(<char *> ob.data, ob.size)

        sundown.bufrelease(ob)
        sundown.bufrelease(ib)

        if hasattr(self.renderer, 'postprocess'):
            result = self.renderer.postprocess(result)

        return result

    def __dealloc__(self):
        if self.markdown is not NULL:
            sundown.sd_markdown_free(self.markdown)
