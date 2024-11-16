import pytest
import queue
import os
import pytest_utils
from pytest_utils.decorators import max_score, visibility, tags
  
from cocotb_test.simulator import run
import cocotb
from cocotb.clock import Clock
from cocotb.regression import TestFactory
from cocotb.utils import get_sim_time
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, with_timeout, First, Combine
from cocotb.types import LogicArray, Range
import json
import random
random.seed(42)

from itertools import product
import sys
_REPO_ROOT = os.getenv('REPO_ROOT')
assert (_REPO_ROOT), "REPO_ROOT must be defined in environment as a non-empty string"
assert (os.path.exists(_REPO_ROOT)), "REPO_ROOT path must exist"
sys.path.append(os.path.join(_REPO_ROOT, "util"))
from utilities import *
DIR_PATH = os.path.dirname(os.path.realpath(__file__))

timescale = "1ps/1ps"
tests = ['reset_test_001'
         ,'reset_test_002'
         ,'reset_test_003'
         ,'reset_test_004'
         ,'single_test_001'
         ,'single_test_002'
         ,'single_test_003'
         ,'single_test_004'
         ,'fuzz_test_001'
         ,'fuzz_test_002'
         ,'fuzz_test_003'
         ,'fuzz_test_004'
         ,'stream_test_001'
         ,'stream_test_002'
         ,'stream_test_003'
         ,'stream_test_004'
         ]

# Admittedly test_each approach is a bit hacky. If we treat Verilog
# parameters as pytest parameters, each parameterization runs all the
# tests within one simulation (fine, but not ideal). The drawback is
# that it is impossible to identify which test failed within a
# parameterization inside the simulation. Instead, we run each test
# individually by listing them as pytest parameters (but not a verilog
# parameters) so that they get tested individually.
@pytest.mark.parametrize("width_p", [7, 32])
@pytest.mark.parametrize("depth_log2_p", [4, 2])
@pytest.mark.parametrize("test_name", tests)
def test_each_runner(test_name, width_p, depth_log2_p):
    # This line must be first
    parameters = dict(locals())
    del parameters['test_name']
    runner(timescale, DIR_PATH, test_name, parameters)

# Opposite above, run all the tests in one simulation but reset
# between tests to ensure that reset is clearing all state.
@pytest.mark.parametrize("width_p", [7, 32])
@pytest.mark.parametrize("depth_log2_p", [4, 2])
@max_score(1)
def test_all_runner(width_p, depth_log2_p):
    # This line must be first
    parameters = dict(locals())
    runner(timescale, DIR_PATH, None, parameters)

async def reset(clk_i, reset_i, cycles, FinishFalling=True):
    # Wait for the next rising edge
    await RisingEdge(clk_i)

    # Always assign inputs on the falling edge
    await FallingEdge(clk_i)
    reset_i.value = 1

    # Always assign inputs on the falling edge
    await ClockCycles(clk_i, cycles, rising=False)
    reset_i.value = 0

    if (not FinishFalling):
        await RisingEdge(clk_i)

async def pretest_sequence(dut, cperiod, pperiod):
    # Set the clock to Z for 10 ns. This helps separate tests.
    dut.pclk_i.value = LogicArray(['z'])
    dut.cclk_i.value = LogicArray(['z'])
    await Timer(10, 'ns')

    pc = Clock(dut.cclk_i, cperiod, 'ns')
    cc = Clock(dut.pclk_i, pperiod, 'ns')

    # Start the clock (soon). Start it low to avoid issues on the first RisingEdge
    cocotb.start_soon(pc.start(start_high=False))
    cocotb.start_soon(cc.start(start_high=True))

async def reset_sequence(dut):
    pclk_i = dut.pclk_i
    preset_i = dut.preset_i
    pready_i = dut.pready_i
    pvalid_o = dut.pvalid_o


    cclk_i = dut.cclk_i
    creset_i = dut.creset_i
    cready_o = dut.cready_o
    cvalid_i = dut.cvalid_i

    pready_i.value = 0
    cvalid_i.value = 0

    p = cocotb.start_soon(reset(pclk_i, preset_i, cycles=10, FinishFalling=True))
    c = cocotb.start_soon(reset(cclk_i, creset_i, cycles=10, FinishFalling=True))
    await Combine(p,c)


    await RisingEdge(pclk_i)
    assert_resolvable(pvalid_o)
    assert pvalid_o.value == 0, f"Error! pvalid_o is 1 after reset at Time {get_sim_time(units='ns')}ns."

    await RisingEdge(cclk_i)
    assert_resolvable(cready_o)
    assert cready_o.value == 1, f"Error! cready_o is 0 after reset at Time {get_sim_time(units='ns')}ns."


def assert_resolvable(s):
    assert s.value.is_resolvable, f"Unresolvable value in {s._path} (x or z in some or all bits) at Time {get_sim_time(units='ns')}ns."

class FifoModel():
    def __init__(self, dut):

        self._dut = dut
        self._data_o = dut.pdata_o
        self._data_i = dut.cdata_i

        # Model the fifo like a simple software queue
        self._q = queue.SimpleQueue()

        self._width_p = dut.width_p.value
        self._depth_log2_p = dut.depth_log2_p.value
        self._deqs = 0
        self._enqs = 0

    def consume(self):
        assert_resolvable(self._data_i)
        self._q.put(self._data_i.value)
        self._enqs += 1

    def produce(self):
        assert_resolvable(self._data_o)
        got = self._data_o.value
        expected = self._q.get()
        assert got == expected, f"Error! Value on deque iteration {self._deqs} does not match expected. Expected: {expected}. Got: {got}"
        self._deqs += 1


class ReadyValidInterface():
    def __init__(self, clk_i, reset_i, ready, valid):
        self._clk_i = clk_i
        self._reset_i = reset_i
        self._ready = ready
        self._valid = valid

    def is_in_reset(self):
        if((not self._reset_i.value.is_resolvable) or self._reset_i.value  == 1):
            return True

    def assert_resolvable(self):
        if(not self.is_in_reset()):
            assert_resolvable(self._valid)
            assert_resolvable(self._ready)

    def is_handshake(self):
        return ((self._valid == 1) and (self._ready == 1))

    async def _wait(self, sig):
        """Wait for valid on the positive edge of the clock"""
        while True:
            await RisingEdge(self._clk_i)
            if (not self.is_in_reset()):
                assert_resolvable(sig)
                if(sig == 1):
                    break

    async def is_ready(self, ns):
        """Wait for ready, raising an exception if it hasn't
        happened after ns nanoseconds of simulation time"""
        # If ns is none, wait indefinitely
        if(ns):
            await with_timeout(self._wait(self._ready), ns, 'ns')
        else:
            await self._wait(self._ready)

    async def is_valid(self, ns):
        """Wait for valid, raising an exception if it hasn't
        happened after ns nanoseconds of simulation time"""
        # If ns is none, wait indefinitely
        if(ns):
            await with_timeout(self._wait(self._valid), ns, 'ns')
        else:
            await self._wait(self._valid)

    async def _handshake(self):
        while True:
            await RisingEdge(self._clk_i)
            if (not self.is_in_reset()):
                self.assert_resolvable()
                if(self.is_handshake()):
                    break

    async def handshake(self, ns):
        """Wait for a handshake, raising an exception if it hasn't
        happened after ns nanoseconds of simulation time"""

        # If ns is none, wait indefinitely
        if(ns):
            await with_timeout(self._handshake(), ns, 'ns')
        else:
            await self._handshake()


class RandomDataGenerator():
    def __init__(self, dut):
        self._dut = dut

    def generate(self):
        value = random.randint(0, (1 << self._dut.width_p.value) - 1)
        return value

class RateGenerator():
    def __init__(self, dut, r):
        self._rate = r

    def generate(self):
        if(self._rate == 0):
            return False
        else:
            return (random.randint(1,int(1/self._rate)) == 1)

class OutputModel():
    def __init__(self, dut, g, l):
        self._clk_i = dut.pclk_i
        self._reset_i = dut.preset_i
        self._ready_i = dut.pready_i
        self._valid_o = dut.pvalid_o

        self._rv = ReadyValidInterface(self._clk_i, self._reset_i,
                                       self._ready_i, self._valid_o)
        self._generator = g
        self._length = l

        self._coro = None

        self._nout = 0

    def start(self):
        """ Start Output Model """
        if self._coro is not None:
            raise RuntimeError("Output Model already started")
        self._coro = cocotb.start_soon(self._run())

    def stop(self) -> None:
        """ Stop Output Model """
        if self._coro is None:
            raise RuntimeError("Output Model never started")
        self._coro.kill()
        self._coro = None

    async def wait(self, t):
        await with_timeout(self._coro, t, 'ns')

    async def wait_cyc(self, t):
        await with_timeout(self._coro, t, 'ns')

    def nproduced(self):
        return self._nout

    async def _run(self):
        """ Output Model Coroutine"""

        self._nout = 0
        clk_i = self._clk_i
        reset_i = self._reset_i
        ready_i = self._ready_i
        valid_o = self._valid_o

        await FallingEdge(clk_i)

        if(not (reset_i.value.is_resolvable and reset_i.value == 0)):
            await FallingEdge(reset_i)

        # Precondition: Falling Edge of Clock
        while self._nout < self._length:
            consume = self._generator.generate()
            success = 0
            ready_i.value = consume

            # Wait until valid, but only read it on the positive edge
            # of the clock.
            while(consume and not success):
                await RisingEdge(clk_i)
                assert_resolvable(valid_o)
                success = True if (valid_o.value == 1) else False
                if (success):
                    self._nout += 1

            await FallingEdge(clk_i)

        return self._nout

class InputModel():
    def __init__(self, dut, data, rate, l):
        self._clk_i = dut.cclk_i
        self._reset_i = dut.creset_i
        self._ready_o = dut.cready_o
        self._valid_i = dut.cvalid_i
        self._data_i = dut.cdata_i

        self._rv = ReadyValidInterface(self._clk_i, self._reset_i,
                                       self._ready_o, self._valid_i)

        self._rate = rate
        self._data = data
        self._length = l

        self._coro = None

        self._nin = 0

    def start(self):
        """ Start Input Model """
        if self._coro is not None:
            raise RuntimeError("Input Model already started")
        self._coro = cocotb.start_soon(self._run())

    def stop(self) -> None:
        """ Stop Input Model """
        if self._coro is None:
            raise RuntimeError("Input Model never started")
        self._coro.kill()
        self._coro = None

    async def wait(self, t):
        await with_timeout(self._coro, t, 'ns')

    def nconsumed(self):
        return self._nin

    async def _run(self):
        """ Input Model Coroutine"""

        self._nin = 0
        clk_i = self._clk_i
        reset_i = self._reset_i
        ready_o = self._ready_o
        valid_i = self._valid_i
        data_i = self._data_i

        await ClockCycles(clk_i, 1, rising=False)

        # If reset is not resolvable, or reset is high, wait until it goes to 0.
        if(not (reset_i.value.is_resolvable and reset_i.value == 0)):
            await FallingEdge(reset_i)

        await ClockCycles(clk_i, 2, rising=False)

        # Precondition: Falling Edge of Clock
        while self._nin < self._length:
            produce = self._rate.generate()
            din = self._data.generate()
            success = 0
            valid_i.value = produce
            data_i.value = din

            # Wait until ready
            while(produce and not success):
                await RisingEdge(clk_i)
                assert_resolvable(ready_o)

                success = True if (ready_o.value == 1) else False
                if (success):
                    self._nin += 1

            await FallingEdge(clk_i)
        return self._nin

class ModelRunner():
    def __init__(self, dut, model):

        self._rv_in = ReadyValidInterface(dut.cclk_i, dut.creset_i,
                                          dut.cready_o, dut.cvalid_i)

        self._rv_out = ReadyValidInterface(dut.pclk_i, dut.preset_i,
                                           dut.pready_i, dut.pvalid_o)

        self._model = model

        self._events = queue.SimpleQueue()

        self._coro_run_in = None
        self._coro_run_out = None

    def start(self):
        """Start model"""
        if self._coro_run_in is not None:
            raise RuntimeError("Model already started")
        self._coro_run_input = cocotb.start_soon(self._run_input(self._model))
        self._coro_run_output = cocotb.start_soon(self._run_output(self._model))

    async def _run_input(self, model):
        while True:
            await self._rv_in.handshake(None)
            self._events.put(get_sim_time(units='ns'))
            self._model.consume()

    async def _run_output(self, model):
        while True:
            await self._rv_out.handshake(None)
            assert (self._events.qsize() > 0), "Error! Module produced output without valid input"
            input_time = self._events.get(get_sim_time(units='ns'))
            self._model.produce()

    def stop(self) -> None:
        """Stop monitor"""
        if self._coro_run is None:
            raise RuntimeError("Monitor never started")
        self._coro_run_input.kill()
        self._coro_run_output.kill()
        self._coro_run_input = None
        self._coro_run_output = None


async def reset_test(dut, pclk_period, cclk_period):
    """Test for Initialization"""

    await pretest_sequence(dut, pclk_period, cclk_period)
    await reset_sequence(dut)

async def single_test(dut, pclk_period, cclk_period):
    """Test to transmit a single element."""

    l = 1
    rate = 1

    m = ModelRunner(dut, FifoModel(dut))
    om = OutputModel(dut, RateGenerator(dut, 1), l)
    im = InputModel(dut, RandomDataGenerator(dut), RateGenerator(dut, rate), l)

    await pretest_sequence(dut, pclk_period, cclk_period)
    await reset_sequence(dut)

    m.start()
    om.start()
    im.start()

    dut.cvalid_i.value = 0
    dut.pready_i.value = 0

async def fill_test(dut, pclk_period, cclk_period):
    """Test if fifo_1r1w fills to depth_p elements"""

    depth_p = (1 << dut.depth_log2_p.value)
    l = depth_p
    rate = 1

    m = ModelRunner(dut, FifoModel(dut))
    om = OutputModel(dut, RateGenerator(dut, 0), l)
    im = InputModel(dut, RandomDataGenerator(dut), RateGenerator(dut, rate), l)

    await pretest_sequence(dut, pclk_period, cclk_period)
    await reset_sequence(dut)

    m.start()
    om.start()
    im.start()

    await im._rv.is_valid(None)

    success = False
    try:
        await im.wait(depth_p)
        success = True
    except:
        nconsumed = im.nconsumed()

    if(not success):
        assert nconsumed != depth_p, f"Error! Could not fill fifo with {depth_p} elements in {depth_p} cycles. Fifo consumed {nconsumed} elements."

async def fill_empty_test(dut, pclk_period, cclk_period):
    """Test if fifo_1r1w fills to depth_p elements, and then empties
    successfully"""

    depth_p = (1 << dut.depth_log2_p.value)
    l = depth_p
    rate = 1

    m = ModelRunner(dut, FifoModel(dut))
    om = OutputModel(dut, RateGenerator(dut, 0), l)
    im = InputModel(dut, RandomDataGenerator(dut), RateGenerator(dut, rate), l)

    await pretest_sequence(dut, pclk_period, cclk_period)
    await reset_sequence(dut)

    m.start()
    om.start()
    im.start()

    await im._rv.is_valid(None)

    success = False
    try:
        await im.wait(depth_p * cclk_period)
        success = True
    except:
        nconsumed = im.nconsumed()

    if(not success):
        assert nconsumed != depth_p, f"Error! Could not fill fifo with {depth_p} elements in {depth_p} cycles. Fifo consumed {nconsumed} elements."

    om = OutputModel(dut, RateGenerator(dut, 1), l)
    om.start()

    try:
        await om._rv.is_ready(100)
    except cocotb.result.SimTimeoutError:
        assert 0, f"Test timed out. Testbench is waiting for pvalid_o, but pvalid_o never went high in 100 clock cycles after reset."

    nproduced = 0
    success = False
    try:
        await om.wait(depth_p * pclk_period)
        success = True
    except:
        nproduced = om.nproduced()

    if(not success):
        assert nproduced != depth_p, f"Error! Could not empty fifo with {depth_p} elements in {depth_p} cycles. Fifo produced {nproduced} elements."

#@cocotb.test()
async def fuzz_test(dut, pclk_period, cclk_period):
    """Transmit 4 * depth_p random data elements at 50% line rate"""

    l = (1 << dut.depth_log2_p.value) * 4
    rate = .5

    timeout = l * int(1/rate) * int(1/rate) * 4 * max(pclk_period, cclk_period)

    m = ModelRunner(dut, FifoModel(dut))
    om = OutputModel(dut, RateGenerator(dut, rate), l)
    im = InputModel(dut, RandomDataGenerator(dut), RateGenerator(dut, rate), l)

    await pretest_sequence(dut, pclk_period, cclk_period)
    await reset_sequence(dut)

    m.start()
    om.start()
    im.start()

    # We're doing a throughput test. We only care about the output
    # throughput.  We can wait for the rising edge of valid_o because
    # it (should, if the circuit is implemented correctly) occur at,
    # or just after the clock edge.
    try:
        await om._rv.is_ready(100)
    except cocotb.result.SimTimeoutError:
        assert 0, f"Test timed out. Testbench is waiting for pvalid_o, but pvalid_o never went high in 100 clock cycles after reset."

    try:
        await om.wait(timeout)
    except cocotb.result.SimTimeoutError:
        assert 0, f"Test timed out. Could not transmit {l} elements in {timeout} ns, with output rate {rate}"

#@cocotb.test()
async def stream_test(dut, pclk_period, cclk_period):
    """Transmit 4 * depth_p random data elements at 100% line rate"""

    # This is the InputModel
    l = (1 << dut.depth_log2_p.value) * 4
    rate = 1

    timeout = max(pclk_period, cclk_period) * l * 2

    m = ModelRunner(dut, FifoModel(dut))
    om = OutputModel(dut, RateGenerator(dut, rate), l)
    im = InputModel(dut, RandomDataGenerator(dut), RateGenerator(dut, rate), l)

    await pretest_sequence(dut, pclk_period, cclk_period)
    await reset_sequence(dut)

    m.start()
    om.start()
    im.start()

    # We're doing a throughput test. We only care about the output
    # throughput.  We can wait for the rising edge of valid_o because
    # it (should, if the circuit is implemented correctly) occur at,
    # or just after the clock edge.
    try:
        await om._rv.is_ready(100)
    except cocotb.result.SimTimeoutError:
        assert 0, f"Test timed out. Testbench is waiting for pvalid_o, but pvalid_o never went high in 100 clock cycles after reset."

    try:
        await om.wait(timeout)
    except cocotb.result.SimTimeoutError:
        assert 0, f"Test timed out. Could not transmit {l} elements in {timeout} ns, with output rate {rate}"

pclk_periods = [1, 5]
cclk_periods = [1, 3.1]
tf = TestFactory(test_function=stream_test)
tf.add_option(name='pclk_period', optionlist=pclk_periods)
tf.add_option(name='cclk_period', optionlist=cclk_periods)
tf.generate_tests()

tf = TestFactory(test_function=fuzz_test)
tf.add_option(name='pclk_period', optionlist=pclk_periods)
tf.add_option(name='cclk_period', optionlist=cclk_periods)
tf.generate_tests()

tf = TestFactory(test_function=fill_test)
tf.add_option(name='pclk_period', optionlist=pclk_periods)
tf.add_option(name='cclk_period', optionlist=cclk_periods)
tf.generate_tests()

tf = TestFactory(test_function=fill_empty_test)
tf.add_option(name='pclk_period', optionlist=pclk_periods)
tf.add_option(name='cclk_period', optionlist=cclk_periods)
tf.generate_tests()

tf = TestFactory(test_function=reset_test)
tf.add_option(name='pclk_period', optionlist=pclk_periods)
tf.add_option(name='cclk_period', optionlist=cclk_periods)
tf.generate_tests()

tf = TestFactory(test_function=single_test)
tf.add_option(name='pclk_period', optionlist=pclk_periods)
tf.add_option(name='cclk_period', optionlist=cclk_periods)
tf.generate_tests()
