import pytest
import queue
import os
import pytest_utils
from pytest_utils.decorators import max_score, visibility, tags
  
import sys
_REPO_ROOT = os.getenv('REPO_ROOT')
assert (_REPO_ROOT), "REPO_ROOT must be defined in environment as a non-empty string"
assert (os.path.exists(_REPO_ROOT)), "REPO_ROOT path must exist"
sys.path.append(os.path.join(_REPO_ROOT, "util"))
from utilities import *

from cocotb_test.simulator import run
import cocotb
from cocotb.clock import Clock
from cocotb.regression import TestFactory
from cocotb.utils import get_sim_time
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, with_timeout
from cocotb.types import LogicArray, Range
import json
import random
import numpy as np
random.seed(42)

from itertools import product

DIR_PATH = os.path.dirname(os.path.realpath(__file__))

timescale = "1ps/1ps"
tests = ['reset_test'
         ,'stream_constant_test'
         ,'fuzz_constant_test'
         ,'stream_audio_test'
         ,'fuzz_audio_test'
         ]

# Admittedly test_each approach is a bit hacky. If we treat Verilog
# parameters as pytest parameters, each parameterization runs all the
# tests within one simulation (fine, but not ideal). The drawback is
# that it is impossible to identify which test failed within a
# parameterization inside the simulation. Instead, we run each test
# individually by listing them as pytest parameters (but not a verilog
# parameters) so that they get tested individually.
@pytest.mark.parametrize("test_name", tests)
@pytest.mark.parametrize("width_p", [10])
def test_each_runner(test_name, width_p):
    # This line must be first
    parameters = dict(locals())
    del parameters['test_name']
    runner(timescale, DIR_PATH, test_name, parameters)

# Opposite above, run all the tests in one simulation but reset
# between tests to ensure that reset is clearing all state.
@max_score(10)
@pytest.mark.parametrize("width_p", [10])
def test_all_runner(width_p):
    # This line must be first
    parameters = dict(locals())
    runner(timescale, DIR_PATH, None, parameters)

async def reset(dut, reset_i, cycles, FinishFalling=True):
    # Wait for the next rising edge
    await RisingEdge(dut.clk_i)

    # Always assign inputs on the falling edge
    await FallingEdge(dut.clk_i)
    reset_i.value = 1

    await ClockCycles(dut.clk_i, cycles)

    # Always assign inputs on the falling edge
    await FallingEdge(dut.clk_i)
    reset_i.value = 0

    reset_i._log.debug("Reset complete")

    # Always assign inputs on the falling edge
    if (not FinishFalling):
        await RisingEdge(dut.clk_i)

async def wait_for_signal(dut, signal, value):
    signal = getattr(dut, signal)
    while(signal.value.is_resolvable and signal.value != value):
        await FallingEdge(dut.clk_i)

async def pretest_sequence(dut):
    # Set the clock to Z for 10 ns. This helps separate tests.
    dut.clk_i.value = LogicArray(['z'])
    await Timer(10, 'ns')

    # Unrealistically fast clock, but nice for mental math (1 GHz)
    c = Clock(dut.clk_i, 1, 'ns')

    # Start the clock (soon). Start it low to avoid issues on the first RisingEdge
    cocotb.start_soon(c.start(start_high=False))

async def reset_sequence(dut):
    clk_i = dut.clk_i
    reset_i = dut.reset_i

    ready_i = dut.ready_i
    valid_i = dut.valid_i
    ready_o = dut.ready_o
    valid_o = dut.valid_o
    data_i = dut.data_i
    data_i.value = 0

    await reset(dut, reset_i, cycles=10, FinishFalling=True)

    ready_i.value = 0
    valid_i.value = 0

    await FallingEdge(clk_i)

    assert_resolvable(valid_o)
    assert valid_o.value == 0, f"Error! valid_o is 1 after reset at Time {get_sim_time(units='ns')}ns."

    assert_resolvable(ready_o)
    assert ready_o.value == 1, f"Error! ready_o is 0 after reset at Time {get_sim_time(units='ns')}ns."

    await FallingEdge(clk_i)

async def delay_cycles(dut, ncyc, polarity):
    for _ in range(ncyc):
        if(polarity):
            await RisingEdge(dut.clk_i)
        else:
            await FallingEdge(dut.clk_i)
    
def assert_resolvable(s):
    assert s.value.is_resolvable, f"Unresolvable value in {s._path} (x or z in some or all bits) at Time {get_sim_time(units='ns')}ns."

class IIRModel():
    def __init__(self, dut):

        self._dut = dut
        self._data_i = dut.data_i
        self._data_o = dut.data_o

        # Model the latency-insensitive mac interface like a simple software queue
        self._q = queue.SimpleQueue()

        self._cur_o = 0
        self._width_p = dut.width_p.value

        self.__b = 0.921875
        self._gots = []
        self._expecteds = []
        self._iter = 0

    def consume(self):
        assert_resolvable(self._data_i)
        self._q.put(self._data_i.value.signed_integer)

    def produce(self):
        assert_resolvable(self._data_o)
        got = self._data_o.value.signed_integer
        data_i = self._q.get()
        self._cur_o = self._cur_o + self.__b * (data_i - self._cur_o)
        expected = int(np.floor(self._cur_o))
        self._gots.append(got)
        self._expecteds.append(expected)
        self._iter += 1
        rmse = self.rmse()
        print(f'On output iteration {self._iter}, expected: {expected}, got: {got}. Running RMSE: {rmse}')

    def rmse(self):
        return np.mean((np.array(self._gots) - np.array(self._expecteds))**2)**.5
        
class ReadyValidInterface():
    def __init__(self, clk, reset, ready, valid):
        self._clk_i = clk
        self._reset_i = reset
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

class SingletonGenerator():
    def __init__(self, dut, v):
        self._value = v

    def generate(self):
        return self._value

class AudioDataGenerator():
    def __init__(self, dut, l):
        self._dut = dut
        width = dut.width_p.value
        self._data = np.rint(np.sin(np.linspace(-np.pi, np.pi, l)) * (1 << (width//2))).astype(int)
        self._loc = 0

    def ninputs(self):
        return len(self._data)

    def generate(self):
        val = self._data[self._loc]
        self._loc += 1
        return val

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
        self._clk_i = dut.clk_i
        self._reset_i = dut.reset_i
        self._dut = dut
        
        self._rv_in = ReadyValidInterface(self._clk_i, self._reset_i,
                                          dut.valid_i, dut.ready_o)

        self._rv_out = ReadyValidInterface(self._clk_i, self._reset_i,
                                           dut.valid_o, dut.ready_i)
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

    def nproduced(self):
        return self._nout

    async def _run(self):
        """ Output Model Coroutine"""

        self._nout = 0
        clk_i = self._clk_i
        ready_i = self._dut.ready_i
        reset_i = self._dut.reset_i
        valid_o = self._dut.valid_o

        await FallingEdge(clk_i)

        if(not (reset_i.value.is_resolvable and reset_i.value == 0)):
            await FallingEdge(reset_i)

        # Precondition: Falling Edge of Clock
        while self._nout < self._length:
            consume = self._generator.generate()
            success = 0
            ready_i.value = consume

            # Wait until valid
            while(consume and not success):
                await RisingEdge(clk_i)
                assert_resolvable(valid_o)
                #assert valid_o.value.is_resolvable, f"Unresolvable value in valid_o (x or z in some or all bits) at Time {get_sim_time(units='ns')}ns."

                success = True if (valid_o.value == 1) else False
                if (success):
                    self._nout += 1

            await FallingEdge(clk_i)
        return self._nout

class InputModel():
    def __init__(self, dut, data, rate, l):
        self._clk_i = dut.clk_i
        self._reset_i = dut.reset_i
        self._dut = dut
        
        self._rv_in = ReadyValidInterface(self._clk_i, self._reset_i,
                                          dut.valid_i, dut.ready_o)

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
        reset_i = self._dut.reset_i
        ready_o = self._dut.ready_o
        valid_i = self._dut.valid_i
        data_i = self._dut.data_i

        data_i.value = 0
        await delay_cycles(self._dut, 1, False)

        if(not (reset_i.value.is_resolvable and reset_i.value == 0)):
            await FallingEdge(reset_i)

        await delay_cycles(self._dut, 2, False)

        data = self._data.generate()
        # Precondition: Falling Edge of Clock
        while self._nin < self._length:
            produce = self._rate.generate()
            success = 0
            valid_i.value = produce
            # TODO: Figure out long term how to abstract this
            data_i.value = int(data)

            # Wait until ready
            while(produce and not success):
                await RisingEdge(clk_i)
                assert_resolvable(ready_o)

                success = True if (ready_o.value == 1) else False
                if (success):
                    self._nin += 1

            # Make sure we're not about to exit the loop
            if((self._nin < self._length) and success ):
                data = self._data.generate()

            await FallingEdge(clk_i)
        return self._nin

class ModelRunner():
    def __init__(self, dut, model):

        self._clk_i = dut.clk_i
        self._reset_i = dut.reset_i

        self._rv_in = ReadyValidInterface(self._clk_i, self._reset_i,
                                          dut.valid_i, dut.ready_o)
        self._rv_out = ReadyValidInterface(self._clk_i, self._reset_i,
                                           dut.valid_o, dut.ready_i)

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
    

@cocotb.test()
async def reset_test(dut):
    """Test for Initialization"""

    await pretest_sequence(dut)
    await reset_sequence(dut)

@cocotb.test()
async def fuzz_constant_test(dut):
    """Stream constant data at 50% line rate"""

    # This is the InputModel
    eg = SingletonGenerator(dut, 16)
    l = 10
    rate = .5

    timeout = l * int(1/rate) * int(1/rate) * 2

    mm = IIRModel(dut)
    m = ModelRunner(dut, mm)
    om = OutputModel(dut, RateGenerator(dut, rate), l)
    im = InputModel(dut, eg, RateGenerator(dut, rate), l)

    await pretest_sequence(dut)
    await reset_sequence(dut)

    # Wait one cycle for reset to start
    await FallingEdge(dut.clk_i)

    m.start()
    om.start()
    im.start()

    try:
        await om.wait(timeout)
    except cocotb.result.SimTimeoutError:
        assert 0, f"Test timed out. Could not transmit {l} elements in {timeout} ns, with output rate {rate}"

    rmse = mm.rmse()
    assert rmse < 1, f"Error! Root Mean Squared Error (RMSE) greater than 1 at end of test"

@cocotb.test()
async def stream_constant_test(dut):
    """Stream constant data at 100% line rate"""

    eg = SingletonGenerator(dut, 16)
    l = 10
    rate = 1

    timeout = l + 4

    mm = IIRModel(dut)
    m = ModelRunner(dut, mm)
    om = OutputModel(dut, RateGenerator(dut, rate), l)
    im = InputModel(dut, eg, RateGenerator(dut, rate), l)

    await pretest_sequence(dut)
    await reset_sequence(dut)

    await FallingEdge(dut.clk_i)

    m.start()
    om.start()
    im.start()

    await RisingEdge(dut.ready_i)
    await RisingEdge(dut.clk_i)
    try:
        await om.wait(timeout)
    except cocotb.result.SimTimeoutError:
        assert 0, f"Test timed out. Could not transmit {l} elements in {timeout} ns, with output rate {rate}"

    rmse = mm.rmse()
    assert rmse < 1, f"Error! Root Mean Squared Error (RMSE) greater than 1 at end of test"

@cocotb.test()
async def fuzz_audio_test(dut):
    """Stream "audio" data at 50% line rate"""

    # This is the InputModel
    l = 100
    eg = AudioDataGenerator(dut, l)
    rate = .5

    timeout = l * int(1/rate) * int(1/rate) * 2

    mm = IIRModel(dut)
    m = ModelRunner(dut, mm)
    om = OutputModel(dut, RateGenerator(dut, rate), l)
    im = InputModel(dut, eg, RateGenerator(dut, rate), l)

    await pretest_sequence(dut)
    await reset_sequence(dut)

    # Wait one cycle for reset to start
    await FallingEdge(dut.clk_i)

    m.start()
    om.start()
    im.start()

    try:
        await om.wait(timeout)
    except cocotb.result.SimTimeoutError:
        assert 0, f"Test timed out. Could not transmit {l} elements in {timeout} ns, with output rate {rate}"

    rmse = mm.rmse()
    assert rmse < 1, f"Error! Root Mean Squared Error (RMSE) greater than 1 at end of test"

@cocotb.test()
async def stream_audio_test(dut):
    """Stream audio data at 100% line rate"""

    l = 100
    eg = AudioDataGenerator(dut, l)
    rate = 1

    timeout = l + 4

    mm = IIRModel(dut)
    m = ModelRunner(dut, mm)
    om = OutputModel(dut, RateGenerator(dut, rate), l)
    im = InputModel(dut, eg, RateGenerator(dut, rate), l)

    await pretest_sequence(dut)
    await reset_sequence(dut)

    await FallingEdge(dut.clk_i)

    m.start()
    om.start()
    im.start()

    await RisingEdge(dut.ready_i)
    await RisingEdge(dut.clk_i)
    try:
        await om.wait(timeout)
    except cocotb.result.SimTimeoutError:
        assert 0, f"Test timed out. Could not transmit {l} elements in {timeout} ns, with output rate {rate}"
        
    rmse = mm.rmse()
    assert rmse < 1, f"Error! Root Mean Squared Error (RMSE) greater than 1 at end of test"
